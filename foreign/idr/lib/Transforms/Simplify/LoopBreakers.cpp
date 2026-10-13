// idr-loop-breakers: every cycle of references among the idr.func that may
// be inlined keeps a loop breaker, in every round of the simplify loop.
//
// The first round marks the breakers of the cycles Emit wrote; Emit marks
// none, so there is one rule for every cycle. The rounds then close
// new cycles: a call redirected to a clone that calls back, or, through
// sccp, a function that returns a closure constant of itself (an IO loop
// whose action is a constant: `echo = getChar >>= \c => ... echo`, where
// `echo` returns the action that `\c` closes over, so `\c` refers to
// itself). A cycle that a redirection closes only once inlining shows how
// a call is consumed (a call of a breaker in the breaker's clone, passed to
// a callee that applies it) is no cycle of references until then: the
// clone carries its callee's no_inline instead (idr-specialize). The
// inliner sees only calls. It refuses only self-recursion and a callee that
// calls its caller back (`Inliner::Impl::shouldInline`), and it blocks a
// recursive call edge, once inlining has unrolled it, only for the rest of
// that inliner run; each round's run starts afresh, so it would unroll
// such a cycle once per round, forever. A function refers to what it calls
// and to the functions its closures and closure constants name. In each
// cycle without a breaker (two or more functions, or one that refers to
// itself), the newest clone becomes `no_inline`, or else the first
// function in module order that does not break last (`break_last`,
// which Emit writes from the registry's column), or else the first; then
// the rest of the cycle is cut the same way.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Simplify.h"
#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/References.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {
#define GEN_PASS_DEF_IDRLOOPBREAKERS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// The breaker of a cycle: its newest clone, or else its first function in
// module order that does not break last, or else its first.
idr::FuncOp choose(ArrayRef<idr::FuncOp> cycle,
                   const llvm::DenseMap<idr::FuncOp, unsigned> &order) {
  idr::FuncOp newest, first, firstEarly;
  for (idr::FuncOp fn : cycle) {
    unsigned at = order.lookup(fn);
    if (fn.getClone() && (!newest || order.lookup(newest) < at))
      newest = fn;
    if (!first || at < order.lookup(first))
      first = fn;
    if (!fn.getBreakLast() && (!firstEarly || at < order.lookup(firstEarly)))
      firstEarly = fn;
  }
  return newest ? newest : firstEarly ? firstEarly : first;
}

// Whether `fn` names itself.
bool namesItself(idr::FuncOp fn, const idr::References &refs) {
  return llvm::any_of(refs.of(fn),
                      [&](const idr::References::Site &site) { return site.target == fn; });
}

// Marks a loop breaker `no_inline` in every cycle of references of
// `module` that has none; returns how many it marked.
unsigned markLoopBreakers(ModuleOp module, const idr::References &refs) {
  llvm::DenseMap<idr::FuncOp, unsigned> order;
  for (idr::FuncOp fn : module.getOps<idr::FuncOp>())
    order.try_emplace(fn, order.size());

  // The functions that may be inlined. Marking a breaker drops that
  // function from the graph and does not change a body's references, so
  // the edges are built once; a later iteration deletes the edges that
  // touch the breaker instead of building a new adjacency.
  SmallVector<idr::FuncOp> nodes;
  llvm::DenseMap<idr::FuncOp, unsigned> index;
  for (idr::FuncOp fn : module.getOps<idr::FuncOp>()) {
    if (fn.isExternal() || fn.getNoInline())
      continue;
    index.try_emplace(fn, nodes.size());
    nodes.push_back(fn);
  }
  // Each node fills only its own list, reading the references and the
  // index, which nothing writes by then; the incoming lists follow in node
  // order, so the graph is the same however many threads built it.
  SmallVector<SmallVector<unsigned>> edges(nodes.size());
  parallelFor(module.getContext(), 0, nodes.size(), [&](size_t at) {
    for (const idr::References::Site &site : refs.of(nodes[at])) {
      auto to = index.find(site.target);
      if (to != index.end())
        edges[at].push_back(to->second);
    }
  });
  SmallVector<SmallVector<unsigned>> incoming(nodes.size());
  for (auto [at, next] : llvm::enumerate(edges))
    for (unsigned to : next)
      incoming[to].push_back(static_cast<unsigned>(at));
  // A dropped function keeps its index, so the others are not renumbered.
  // No edge is left in or out of it, and it is then a component of its own.
  SmallVector<bool> live(nodes.size(), true);
  auto drop = [&](unsigned at) {
    live[at] = false;
    for (unsigned from : incoming[at])
      llvm::erase(edges[from], at);
    edges[at].clear();
    incoming[at].clear();
  };

  unsigned marked = 0;
  for (bool again = true; again;) {
    again = false;
    for (const SmallVector<unsigned> &component : idr::components(edges)) {
      if (!llvm::all_of(component, [&](unsigned vertex) { return live[vertex]; }))
        continue;
      SmallVector<idr::FuncOp> cycle;
      for (unsigned vertex : component)
        cycle.push_back(nodes[vertex]);
      if (cycle.size() == 1 && !namesItself(cycle.front(), refs))
        continue;
      idr::FuncOp breaker = choose(cycle, order);
      breaker.setNoInline(true);
      drop(index.find(breaker)->second);
      ++marked;
      again = true;
    }
  }
  return marked;
}

struct LoopBreakers : idr::impl::IdrLoopBreakersBase<LoopBreakers> {
  void runOnOperation() override {
    unsigned marked = markLoopBreakers(getOperation(), getAnalysis<idr::References>());
    numBreakers += marked;
    if (!marked)
      return markAllAnalysesPreserved();
    // Only no_inline changed, which none of these reads; References kept
    // is what lets the round's facts compute the binding times on the
    // references idr-effects found.
    markAnalysesPreserved<SymbolTable, idr::References, idr::Effects, idr::Holds, idr::TypeGraph,
                          idr::Layouts>();
  }
};

} // namespace
