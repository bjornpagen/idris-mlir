// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-effects: `effects` on every idr.func of a first-order program, by the
// one driver (solveEffects), component by component of the call graph,
// callees first, with nothing optimized between: what idr-optimize's ready
// set writes for a component once it is final, here for every component at
// once.
//
// Only defunctionalization's label solve knows what an apply runs, or a
// force of a suspension, so a program at the higher stage is refused here
// rather than summarized as if those ran nothing.
#include "idr/Transforms/Effects.h"

#include "idr/Analysis/Effects.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/SymbolTable.h"

namespace idr {
#define GEN_PASS_DEF_IDREFFECTS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct IdrEffectsPass : idr::impl::IdrEffectsBase<IdrEffectsPass> {
  void runOnOperation() override {
    idr::ProgramOp program = getOperation();
    if (program.getStage() == idr::Stage::Higher) {
      program.emitError("idr-effects runs on a first-order program, after idr-defunctionalize");
      return signalPassFailure();
    }
    idr::solveEffects(program);
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>()) {
      idr::Effect entry = fn.getEffects();
      numIO += idr::bitEnumContainsAny(entry, idr::Effect::io);
      numCrash += idr::bitEnumContainsAny(entry, idr::Effect::crash);
      numDiverge += idr::bitEnumContainsAny(entry, idr::Effect::diverge);
    }
    // Only facts on functions changed.
    markAnalysesPreserved<SymbolTable>();
  }
};

} // namespace
