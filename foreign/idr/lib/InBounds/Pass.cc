// idr-in-bounds: every guard that can never crash is erased, as
// idr.inbounds proves it.

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
