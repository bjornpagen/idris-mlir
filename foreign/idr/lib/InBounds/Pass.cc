// idr-in-bounds: the array accesses proven within their arrays are marked
// `in_bounds`, as idr.inbounds proves them.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRINBOUNDS
#include "idr/Passes.h.inc"
} // namespace idr

import idr.inbounds;

namespace {

struct InBounds : idr::impl::IdrInBoundsBase<InBounds> {
  using IdrInBoundsBase::IdrInBoundsBase;

  void runOnOperation() override {
    mlir::FailureOr<idr::inbounds::Proved> done = idr::inbounds::prove(getOperation());
    if (mlir::failed(done))
      return signalPassFailure();
    numProved += done->proved;
    numChecked += done->checked;
  }
};

} // namespace
