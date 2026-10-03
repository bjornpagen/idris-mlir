// idr-effects: `idr.effects` on every function (idr.facts reads it), as
// idr.facts infers it.
#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDREFFECTS
#include "idr/Passes.h.inc"
} // namespace idr

import idr.facts;

namespace {

struct Effects : idr::impl::IdrEffectsBase<Effects> {
  void runOnOperation() override {
    for (auto [fn, effects] : idr::facts::infer(getOperation())) {
      numIO += effects.io;
      numCrash += effects.crash;
      numDiverge += effects.diverge;
      idr::facts::record(fn, effects);
    }
  }
};

} // namespace
