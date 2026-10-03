// every-cycle-has-breaker: inlining ends because every cycle of references
// among the functions it may inline is cut by a loop breaker (no_inline).
// Which function of a cycle breaks it is the passes' choice; that one
// does is the property.
export module idr.expect:everyCycleHasBreaker;

import idr.mlir;
import idr.graph;

import :references;
import :report;

using namespace mlir;

namespace idr::expect {

// Every cycle of references among functions has a loop breaker.
export LogicalResult everyCycleHasBreaker(ModuleOp module, StringRef) {
  SymbolTable symbols(module);
  auto refers = [&](func::FuncOp fn) { return references(symbols, fn); };
  SmallVector<func::FuncOp> inlinable;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal() && !fn.getNoInline())
      inlinable.push_back(fn);
  bool held = true;
  for (const SmallVector<func::FuncOp> &cycle :
       idr::graph::stronglyConnected<func::FuncOp>(inlinable, refers)) {
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
