// idr-isolate: every idr.lambda and idr.delay becomes an idr.closure or
// idr.suspend of a function of its own, as idr.isolate outlines it.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRISOLATE
#include "idr/Passes.h.inc"
} // namespace idr

import idr.isolate;

namespace {

struct Isolate : idr::impl::IdrIsolateBase<Isolate> {
  void runOnOperation() override {
    if (mlir::failed(idr::isolate::outline(getOperation())))
      signalPassFailure();
  }
};

} // namespace
