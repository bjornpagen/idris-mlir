// folds-balanced: the folders call the runtime natively, and every owned
// reference they take from it they release, so no fold leaves a cell live.
// What each fold left is counted on the context, so the check holds
// whatever threads folded.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// The folders released every reference they took from the runtime: no
// fold, on any thread, left a cell live. idr-expect loads the idr dialect,
// which holds the count.
LogicalResult foldsBalanced(ModuleOp module, AnalysisManager &, StringRef) {
  int64_t left = module->getContext()->getLoadedDialect<IdrDialect>()->foldLeakCount();
  if (left == 0)
    return success();
  fail(module.getLoc(), "folds-balanced") << left << " cells the folders left live";
  return failure();
}

} // namespace idr::expect
