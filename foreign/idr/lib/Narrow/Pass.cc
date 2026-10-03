// idr-narrow: the bigs and naturals integer range analysis proves fit a
// small become plain i64 words, and a loop whose natural only descends is
// versioned so that its copy proves it, as idr.narrow narrows them.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRNARROW
#include "idr/Passes.h.inc"
} // namespace idr

import idr.narrow;

namespace {

struct Narrow : idr::impl::IdrNarrowBase<Narrow> {
  using IdrNarrowBase::IdrNarrowBase;

  void runOnOperation() override {
    mlir::FailureOr<idr::narrow::Narrowed> done = idr::narrow::narrow(getOperation());
    if (mlir::failed(done))
      return signalPassFailure();
    numVersioned += done->versioned;
    numCarried += done->carried;
    numNarrowed += done->narrowed;
  }
};

} // namespace
