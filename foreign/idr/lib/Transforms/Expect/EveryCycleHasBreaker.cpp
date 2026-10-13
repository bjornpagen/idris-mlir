// every-cycle-has-breaker: inlining ends because every cycle of references
// among the functions it may inline is cut by a loop breaker (no_inline).
// Which function of a cycle breaks it is the passes' choice; that one
// does is the property.

#include "idr/Transforms/Expect.h"

#include "idr/Analysis/References.h"
#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

LogicalResult everyCycleHasBreaker(ModuleOp module, AnalysisManager &analyses, StringRef) {
  SmallVector<Operation *> inlinable;
  for (FuncOp fn : module.getOps<FuncOp>())
    if (!fn.isExternal() && !fn.getNoInline())
      inlinable.push_back(fn);
  References &references = analyses.getAnalysis<References>();
  auto edges = [&](Operation *fn) { return referencedBy(references, fn); };
  bool held = true;
  for (const SmallVector<Operation *> &cycle : cycles(inlinable, edges)) {
    InFlightDiagnostic error = fail(cycle.front()->getLoc(), "every-cycle-has-breaker")
                               << "no loop breaker in the cycle of";
    for (Operation *fn : cycle)
      error << " " << where(fn);
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
