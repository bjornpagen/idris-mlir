// idr-prune: code that dead-code analysis proves unreachable is emptied
// before remove-dead-values sees it, as idr.simplify prunes it.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDRPRUNE
#include "idr/Passes.h.inc"
} // namespace idr

import idr.simplify;

namespace {

struct Prune : idr::impl::IdrPruneBase<Prune> {
  void runOnOperation() override {
    mlir::FailureOr<idr::simplify::Pruned> pruned = idr::simplify::prune(getOperation());
    if (mlir::failed(pruned))
      return signalPassFailure();
    numEmptied += pruned->emptied;
    if (!pruned->emptied)
      markAllAnalysesPreserved();
  }
};

} // namespace
