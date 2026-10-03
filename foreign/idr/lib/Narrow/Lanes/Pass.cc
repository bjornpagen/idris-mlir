// idr-narrow-lanes: the integer lanes of a vectorized loop compute in 32
// bits under a runtime bound on its index space, as idr.narrow versions it.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRNARROWLANES
#include "idr/Passes.h.inc"
} // namespace idr

import idr.narrow;

namespace {

struct NarrowLanes : idr::impl::IdrNarrowLanesBase<NarrowLanes> {
  using IdrNarrowLanesBase::IdrNarrowLanesBase;

  void runOnOperation() override {
    mlir::FailureOr<idr::narrow::Lanes> done = idr::narrow::narrowLanes(getOperation());
    if (mlir::failed(done))
      return signalPassFailure();
    numNarrowed += done->narrowed;
    numWide += done->wide;
  }
};

} // namespace
