// folds-balanced: the folders call the runtime natively, and every owned
// reference they take from it they release, so the runtime holds no live
// cell after them. The count is the calling thread's, so a test that
// states it runs single-threaded.

#include "Expect/Expect.h"

#include "idris_rt.h"

using namespace mlir;

namespace idr::expect {

LogicalResult foldsBalanced(ModuleOp module, StringRef) {
  uint64_t live = idris_rt_live_cells();
  if (live == 0)
    return success();
  fail(module.getLoc(), "folds-balanced") << live << " cells the folders made are still live";
  return failure();
}

} // namespace idr::expect
