// idr-tail-loops: self tail calls become loops, as idr.tail makes them.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRTAILLOOPS
#include "idr/Passes.h.inc"
} // namespace idr

import idr.tail;

namespace {

struct TailLoops : idr::impl::IdrTailLoopsBase<TailLoops> {
  void runOnOperation() override {
    mlir::FailureOr<idr::tail::Loops> made = idr::tail::makeLoops(getOperation());
    if (mlir::failed(made))
      return signalPassFailure();
    numLoops += made->loops;
    numCounted += made->counted;
  }
};

} // namespace
