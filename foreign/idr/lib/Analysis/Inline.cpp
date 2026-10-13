// The inline decisions, in three phases: what each function names, read
// from References in parallel, one slot per function; the counts of calls,
// merged in module order, and the components of the call graph; the rule,
// from the callees up.

#include "idr/Analysis/Inline.h"

#include "idr/Analysis/References.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"

using namespace mlir;

namespace {

constexpr int64_t kLeafSize = 40;
constexpr int64_t kSmall = 60;
constexpr int64_t kProduct = 320;

// What one function names: its call sites but a self call, in walk order
// with repeats; the targets of its other sites, itself included; one edge
// per callee, at its first call, none to a loop breaker; whether it calls
// itself.
struct Slot {
  llvm::SmallVector<idr::FuncOp> calls;
  llvm::SmallVector<idr::FuncOp> named;
  llvm::SmallVector<idr::FuncOp> edges;
  bool selfCall = false;
};

} // namespace

namespace idr {

// A leaf function, one that calls nothing (an apply calls something), is
// inlined when it has at most kLeafSize ops. Any other function is inlined
// when (calls - 1) * (size - kSmall) <= kProduct: a function under kSmall
// ops always is, a larger one only while its copies stay within kProduct
// ops. Its calls are its call sites and the closures that name it, since
// each closure becomes a call where it is applied. A function on a cycle of
// calls never is, since inlining it would unroll the cycle; the cycles are
// those that remain once the loop breakers (no_inline) cut every cycle of
// references, so that the other functions of a loop inline into its breaker
// and its recursion becomes a self call. The decisions are taken once,
// before anything is inlined, from the callees up, a callee that will be
// inlined counting with its size where it is called.
InlineDecisions::InlineDecisions(Operation *module, AnalysisManager &am) {
  const References &references = am.getAnalysis<References>();
  llvm::SmallVector<FuncOp> functions;
  llvm::DenseMap<Operation *, unsigned> position;
  for (FuncOp fn : references.functions()) {
    if (fn.isExternal())
      continue;
    position.try_emplace(fn, static_cast<unsigned>(functions.size()));
    functions.push_back(fn);
  }

  // Each slot reads References and its targets' no_inline, and writes only
  // itself.
  llvm::SmallVector<Slot> slots(functions.size());
  parallelFor(module->getContext(), 0, functions.size(), [&](size_t at) {
    FuncOp fn = functions[at];
    Slot &slot = slots[at];
    // Scanning the edges gathered so far at every later call would be
    // quadratic in the calls of this function.
    llvm::SmallDenseSet<Operation *, 8> edged;
    for (const References::Site &site : references.of(fn)) {
      FuncOp target = site.target;
      if (!isa<CallOp>(site.at)) {
        slot.named.push_back(target);
        continue;
      }
      if (target == fn) {
        slot.selfCall = true;
        continue;
      }
      slot.calls.push_back(target);
      if (!target.getNoInline() && edged.insert(target).second)
        slot.edges.push_back(target);
    }
  });

  // A count lands on another function, so the slots are merged here.
  llvm::DenseMap<Operation *, int64_t> callsOf;
  for (const Slot &slot : slots) {
    for (FuncOp target : slot.calls)
      ++callsOf[target];
    for (FuncOp target : slot.named)
      ++callsOf[target];
  }

  llvm::DenseMap<Operation *, int64_t> sizes;
  for (const llvm::SmallVector<FuncOp> &component : stronglyConnected<FuncOp>(
           functions, [&](FuncOp fn) { return slots[position.lookup(fn)].edges; })) {
    if (component.size() != 1)
      continue;
    FuncOp fn = component.front();
    const Slot &slot = slots[position.lookup(fn)];
    if (fn.getNoInline() || slot.selfCall)
      continue;
    int64_t size = references.ops(fn);
    for (FuncOp target : slot.calls)
      if (chosen.contains(target))
        size += sizes.lookup(target) - 1;
    sizes[fn] = size;
    bool leaf = !references.hasCall(fn) && size <= kLeafSize;
    if (leaf || (callsOf.lookup(fn) - 1) * (size - kSmall) <= kProduct) {
      chosen.insert(fn);
      leafCount += leaf;
    }
  }

  for (const Slot &slot : slots)
    for (FuncOp target : slot.calls)
      callCount += chosen.contains(target);
}

bool InlineDecisions::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<InlineDecisions>() || !pa.isPreserved<References>();
}

} // namespace idr
