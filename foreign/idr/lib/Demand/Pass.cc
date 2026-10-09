// idr-demand: checks the promises it is given, as idr.demand states them,
// and changes nothing; with none it does nothing. An unknown promise is an
// error, so a misspelled one cannot pass.

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
    ModuleOp module = getOperation();
    bool failed = false;
    for (StringRef promise : promises) {
      if (promise == "in-place") {
        failed |= mlir::failed(idr::demand::inPlace(module));
        continue;
      }
      module.emitError() << "idr-demand: no promise named " << promise;
      failed = true;
    }
    markAllAnalysesPreserved();
    if (failed)
      signalPassFailure();
  }
};

} // namespace
