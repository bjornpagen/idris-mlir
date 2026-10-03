// folds-balanced: the folders call the runtime natively, and every owned
// reference they take from it they release, so the runtime holds no live
// cell after them. The count is the calling thread's, so a test that
// states it runs single-threaded.
module;
// The runtime's C ABI: the folders' count of live cells.
#include "idris_rt.h"

export module idr.expect:folds;

import idr.mlir;
import idr.dialect;

import :report;

using namespace mlir;

namespace idr::expect {

// The folders released every reference they took from the runtime: it holds
// no live cell (on the calling thread).
export LogicalResult foldsBalanced(ModuleOp module, StringRef) {
  uint64_t live = idris_rt_live_cells();
  if (live == 0)
    return success();
  fail(module.getLoc(), "folds-balanced") << live << " cells the folders made are still live";
  return failure();
}

} // namespace idr::expect
