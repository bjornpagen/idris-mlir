// idr-tail-calls: every call the program makes in tail position on a cycle
// of calls is a guaranteed tail call, as idr.lower's makeTailCalls does it.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRTAILCALLS
#include "idr/Passes.h.inc"
} // namespace idr

import idr.lower;

namespace {

struct TailCalls : idr::impl::IdrTailCallsBase<TailCalls> {
  using IdrTailCallsBase::IdrTailCallsBase;

  void runOnOperation() override {
    idr::lower::TailCallCounts counts;
    mlir::LogicalResult made = idr::lower::makeTailCalls(getOperation(), counts);
    numFrameBound += counts.frameBound;
    numInMemory += counts.inMemory;
    numTailCalls += counts.tailCalls;
    if (mlir::failed(made))
      signalPassFailure();
  }
};

} // namespace
