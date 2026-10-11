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
    mlir::ModuleOp module = getOperation();
    // Nothing here adds, erases or renames a symbol. A type is walked once
    // for a world, and that walk looks each declaration up in one table.
    mlir::SymbolTable table(module);
    idr::SymbolScope scope(module, table);
    idr::HoldMemo memo(module.getContext());
    for (auto [fn, effects] : idr::facts::infer(module)) {
      numIO += effects.io;
      numCrash += effects.crash;
      numDiverge += effects.diverge;
      idr::facts::record(fn, effects);
    }
  }
};

} // namespace
