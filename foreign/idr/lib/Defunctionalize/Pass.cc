// idr-defunctionalize: closures of known labels become sums, as
// idr.defunctionalize converts them.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRDEFUNCTIONALIZE
#include "idr/Passes.h.inc"
} // namespace idr

import idr.defunctionalize;

namespace {

struct Defunctionalize : idr::impl::IdrDefunctionalizeBase<Defunctionalize> {
  void runOnOperation() override {
    mlir::FailureOr<idr::defunctionalize::Defunctionalized> done =
        idr::defunctionalize::defunctionalize(getOperation());
    if (mlir::failed(done))
      return signalPassFailure();
    numSums += done->sums;
    numClosures += done->closures;
  }
};

} // namespace
