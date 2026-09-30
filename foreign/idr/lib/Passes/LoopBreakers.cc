// idr-loop-breakers: every cycle of references among the functions that may
// be inlined keeps a loop breaker, at the start of every round
// of the simplify loop.
//
// Emit marks the breakers of full Core's call graph. The rounds then close
// new cycles: a call redirected to a clone that calls back, or, through
// sccp, a function that returns a closure constant of itself (an IO loop
// whose action is a constant: `echo = getChar >>= \c => ... echo`, where
// `echo` returns the action that `\c` closes over, so `\c` refers to
// itself). The inliner sees only calls and refuses only self-recursion and
// a callee that calls its caller back (Inliner.cpp:709-715), so it would
// unroll such a cycle once per round, forever. A function refers to what it
// calls and to the functions its closures and closure constants name. In
// each cycle without a breaker (two or more functions, or one that refers
// to itself), the newest clone becomes `no_inline`, or else the first
// function in module order that is not from a library; then the rest of the
// cycle is cut the same way.

#include "Passes/Scc.h"
#include "idr/Idr.h"

#include "mlir/IR/SymbolTable.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRLOOPBREAKERS
#include "idr/Passes.h.inc"
} // namespace idr

import idr.facts;

namespace {

// The breaker of a cycle: its newest clone, or else its first function in
// module order that is not from a library, or else its first.
func::FuncOp choose(ArrayRef<func::FuncOp> cycle,
                    const llvm::DenseMap<func::FuncOp, unsigned> &order) {
  func::FuncOp newest, first, firstOwn;
  for (func::FuncOp fn : cycle) {
    unsigned at = order.lookup(fn);
    if (fn->hasAttr("idr.clone") && (!newest || order.lookup(newest) < at))
      newest = fn;
    if (!first || at < order.lookup(first))
      first = fn;
    if (!idr::facts::isLibrary(fn) && (!firstOwn || at < order.lookup(firstOwn)))
      firstOwn = fn;
  }
  return newest ? newest : firstOwn ? firstOwn : first;
}

struct LoopBreakers : idr::impl::IdrLoopBreakersBase<LoopBreakers> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    SymbolTable symbols(module);
    llvm::DenseMap<func::FuncOp, unsigned> order;
    for (auto fn : module.getOps<func::FuncOp>())
      order.try_emplace(fn, order.size());

    auto refers = [&](func::FuncOp fn) {
      SmallVector<func::FuncOp> out;
      if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&fn.getBody()))
        for (const SymbolTable::SymbolUse &use : *uses)
          if (auto target = symbols.lookup<func::FuncOp>(use.getSymbolRef().getRootReference()))
            out.push_back(target);
      return out;
    };

    bool marked = false;
    for (bool again = true; again;) {
      again = false;
      SmallVector<func::FuncOp> inlinable;
      for (auto fn : module.getOps<func::FuncOp>())
        if (!fn.isExternal() && !fn.getNoInline())
          inlinable.push_back(fn);
      for (const SmallVector<func::FuncOp> &cycle :
           idr::passes::stronglyConnected<func::FuncOp>(inlinable, refers)) {
        if (cycle.size() == 1 && !llvm::is_contained(refers(cycle.front()), cycle.front()))
          continue;
        func::FuncOp breaker = choose(cycle, order);
        breaker.setNoInline(true);
        ++numBreakers;
        marked = again = true;
      }
    }
    if (!marked)
      markAllAnalysesPreserved();
  }
};

} // namespace
