// idr-stack: a box whose cell never leaves its frame is built on the stack,
// as idr.stack decides.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRSTACK
#include "idr/Passes.h.inc"
} // namespace idr

import idr.stack;

namespace {

struct Stack : idr::impl::IdrStackBase<Stack> {
  void runOnOperation() override {
    mlir::FailureOr<idr::stack::Marked> marked = idr::stack::mark(getOperation());
    if (mlir::failed(marked))
      return signalPassFailure();
    numBoxes += marked->boxes;
    numCells += marked->cells;
  }
};

} // namespace
