// idr-effects: `idr.effects` on every function (idr.facts reads it), as
// idr.facts infers it. The answers stay on this pass. A round of
// idr-simplify runs it again on the same module; a function whose body
// changed is inferred again, and one whose body is unchanged is reused.
#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDREFFECTS
#include "idr/Passes.h.inc"
} // namespace idr

import idr.facts;

namespace {

struct Effects : idr::impl::IdrEffectsBase<Effects> {
  Effects() = default;
  // A copy is another run, on its own module. The functions already inferred
  // belong to the module this pass ran on.
  Effects(const Effects &other) : idr::impl::IdrEffectsBase<Effects>(other) {}

  void runOnOperation() override {
    mlir::ModuleOp module = getOperation();
    bool wrote = false;
    for (auto [fn, effects] : inferred.infer(module)) {
      numIO += effects.io;
      numCrash += effects.crash;
      numDiverge += effects.diverge;
      wrote |= idr::facts::record(fn, effects);
    }
    // Every function already carried these effects, so nothing was
    // rewritten. Preserving every analysis skips the walk of every nested
    // operation.
    if (!wrote)
      markAllAnalysesPreserved();
  }

  idr::facts::Inferred inferred;
};

} // namespace
