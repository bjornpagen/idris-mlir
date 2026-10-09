// idr-demand: checks the in-place promise when it is asked to, as
// idr.demand states it, and changes nothing.

#include "idr/Idr.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRDEMAND
#include "idr/Passes.h.inc"
} // namespace idr

import idr.demand;

namespace {

struct Demand : idr::impl::IdrDemandBase<Demand> {
  using IdrDemandBase::IdrDemandBase;

  void runOnOperation() override {
    markAllAnalysesPreserved();
    if (inPlace && failed(idr::demand::inPlace(getOperation())))
      signalPassFailure();
  }
};

} // namespace
