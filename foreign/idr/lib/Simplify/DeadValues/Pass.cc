// idr-dead-values: remove-dead-values, leaving a call it does not change
// where it is, as idr.simplify removes dead values.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRDEADVALUES
#include "idr/Passes.h.inc"
} // namespace idr

import idr.simplify;

namespace {

struct DeadValues : idr::impl::IdrDeadValuesBase<DeadValues> {
  void runOnOperation() override {
    mlir::FailureOr<bool> changed = idr::simplify::removeDeadValues(getOperation());
    if (failed(changed))
      return signalPassFailure();
    if (!*changed)
      markAllAnalysesPreserved();
  }
};

} // namespace
