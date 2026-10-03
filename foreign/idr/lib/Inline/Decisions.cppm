// idr.inlining:decisions: which functions idr-inline inlines.
export module idr.inlining:decisions;

import idr.mlir;
import idr.dialect;
import idr.graph;

using namespace mlir;

namespace idr::inlining {

namespace {

constexpr int64_t kLeafSize = 40;
constexpr int64_t kSmall = 60;
constexpr int64_t kProduct = 320;

} // namespace

// The functions to inline, and how many of them are leaves.
export struct Decisions {
  llvm::DenseSet<Operation *> inlined;
  unsigned leaves = 0;
};

// The decisions for `module`.
//
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
export Decisions decide(ModuleOp module) {
  SymbolTable symbols(module);
  SmallVector<func::FuncOp> functions;
  llvm::DenseMap<func::FuncOp, SmallVector<func::FuncOp>> callees;
  llvm::DenseMap<func::FuncOp, int64_t> calls;
  llvm::DenseSet<func::FuncOp> leaves, selfCalls;
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal())
      continue;
    functions.push_back(fn);
    bool leaf = true;
    fn.getBody().walk([&](Operation *op) {
      if (isa<CallOpInterface>(op))
        leaf = false;
      if (auto call = dyn_cast<func::CallOp>(op)) {
        auto target = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
        if (!target)
          return;
        if (target == fn) {
          selfCalls.insert(fn);
          return;
        }
        ++calls[target];
        if (!target.getNoInline() && !llvm::is_contained(callees[fn], target))
          callees[fn].push_back(target);
        return;
      }
      if (auto closure = dyn_cast<idr::ClosureOp>(op)) {
        if (auto target = symbols.lookup<func::FuncOp>(closure.getCalleeAttr().getAttr()))
          ++calls[target];
        return;
      }
      op->getAttrDictionary().walk([&](idr::ClosureAttr closure) {
        if (auto target = symbols.lookup<func::FuncOp>(closure.getCallee().getAttr()))
          ++calls[target];
      });
    });
    if (leaf)
      leaves.insert(fn);
  }

  Decisions out;
  llvm::DenseMap<func::FuncOp, int64_t> sizes;
  // Tarjan's components come callees first.
  for (const SmallVector<func::FuncOp> &component :
       idr::graph::stronglyConnected<func::FuncOp>(
           functions, [&](func::FuncOp fn) { return callees.lookup(fn); })) {
    if (component.size() != 1)
      continue;
    func::FuncOp fn = component.front();
    if (fn.getNoInline() || selfCalls.contains(fn))
      continue;
    int64_t size = 0;
    fn.getBody().walk([&](Operation *op) {
      ++size;
      if (auto call = dyn_cast<func::CallOp>(op)) {
        auto target = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
        if (target && out.inlined.contains(target.getOperation()))
          size += sizes.lookup(target) - 1;
      }
    });
    sizes[fn] = size;
    bool leaf = leaves.contains(fn) && size <= kLeafSize;
    if (leaf || (calls.lookup(fn) - 1) * (size - kSmall) <= kProduct) {
      out.inlined.insert(fn.getOperation());
      out.leaves += leaf;
    }
  }
  return out;
}

} // namespace idr::inlining
