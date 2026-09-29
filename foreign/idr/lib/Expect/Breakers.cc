// every-cycle-has-breaker: inlining ends because every cycle of references
// among the functions it may inline is cut by a loop breaker (no_inline).
// Which function of a cycle breaks it is the passes' choice; that one
// does is the property.

#include "Expect/Expect.h"
#include "Passes/Scc.h"

using namespace mlir;

namespace idr::expect {

LogicalResult everyCycleHasBreaker(ModuleOp module, StringRef) {
  SymbolTable symbols(module);
  // A function refers to what it calls and to the functions its closures
  // and closure constants name.
  auto refers = [&](func::FuncOp fn) {
    SmallVector<func::FuncOp> out;
    if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&fn.getBody()))
      for (const SymbolTable::SymbolUse &use : *uses)
        if (auto target = symbols.lookup<func::FuncOp>(use.getSymbolRef().getRootReference()))
          out.push_back(target);
    return out;
  };
  SmallVector<func::FuncOp> inlinable;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal() && !fn.getNoInline())
      inlinable.push_back(fn);
  bool held = true;
  for (const SmallVector<func::FuncOp> &cycle :
       idr::passes::stronglyConnected<func::FuncOp>(inlinable, refers)) {
    if (cycle.size() == 1 && !llvm::is_contained(refers(cycle.front()), cycle.front()))
      continue;
    func::FuncOp first = cycle.front();
    InFlightDiagnostic error = fail(first.getLoc(), "every-cycle-has-breaker")
                               << "no loop breaker in the cycle of";
    for (func::FuncOp fn : cycle)
      error << " @" << fn.getSymName();
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
