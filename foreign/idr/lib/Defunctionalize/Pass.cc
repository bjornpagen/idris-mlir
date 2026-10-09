// idr-defunctionalize: closures and suspensions of known labels become sums,
// as idr.defunctionalize converts them. A key it cannot convert is a value
// nothing lowers, so the program is rejected where the analysis lost it.

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
    for (const idr::defunctionalize::UnknownKey &key : done->unknown) {
      if (key.lazy)
        key.at->emitError() << "unsupported (laziness): a suspension reaches '"
                            << key.at->getName() << "', where the analysis of its labels loses it";
      else
        key.at->emitError() << "unsupported (runtime closure): a closure reaches '"
                            << key.at->getName() << "', where the analysis of its labels loses it";
    }
    if (!done->unknown.empty())
      return signalPassFailure();
    numSums += done->sums;
    numClosures += done->closures;
  }
};

} // namespace
