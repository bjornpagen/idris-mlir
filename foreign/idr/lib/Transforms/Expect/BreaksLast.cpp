// breaks-last: a cycle that holds a function that does not break last
// never breaks at one that does, unless at a clone, the newest of which
// breaks its cycle whatever it is.

#include "idr/Transforms/Expect.h"

#include "idr/Analysis/References.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/DenseSet.h"

using namespace mlir;

namespace idr::expect {

// A breaker that breaks last, and is no clone, was chosen in a cycle of
// functions that all break last: it is on a cycle of such functions still.
LogicalResult breaksLast(ModuleOp module, AnalysisManager &analyses, StringRef) {
  SmallVector<Operation *> last;
  for (FuncOp fn : module.getOps<FuncOp>())
    if (!fn.isExternal() && fn.getBreakLast())
      last.push_back(fn);
  References &references = analyses.getAnalysis<References>();
  auto edges = [&](Operation *fn) { return referencedBy(references, fn); };
  llvm::DenseSet<Operation *> onCycle;
  for (const SmallVector<Operation *> &cycle : cycles(last, edges))
    onCycle.insert(cycle.begin(), cycle.end());
  bool held = true;
  for (Operation *op : last) {
    auto fn = cast<FuncOp>(op);
    if (!fn.getNoInline() || fn.getCloneAttr() || onCycle.contains(op))
      continue;
    fail(fn.getLoc(), "breaks-last")
        << where(fn) << " breaks last, and breaks a cycle that holds a function that does not";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
