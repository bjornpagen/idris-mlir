// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-effects: `effects` on every idr.func of a first-order program and on
// every idr.call, by the one driver (solveEffects), component by component
// of the call graph, callees first, with nothing optimized between: what
// idr-optimize's ready set writes for a component once it is final, here
// for every component at once. Only defunctionalization's label solve knows
// what an apply runs, or a force of a suspension, so the pass runs at the
// first-order stage, which its record declares.
#include "idr/Transforms/Effects.h"

#include "idr/Analysis/CallCycles.h"
#include "idr/Analysis/Effects.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/SymbolTable.h"

namespace idr {
#define GEN_PASS_DEF_IDREFFECTS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

struct IdrEffectsPass : idr::impl::IdrEffectsBase<IdrEffectsPass> {
  void runOnProgram(idr::ProgramOp program) override {
    // Every call is written with its callee.
    idr::solveEffects(program, getAnalysis<idr::CallCycles>());
    for (idr::FuncOp fn : program.getOps<idr::FuncOp>()) {
      idr::Effect entry = fn.getEffects();
      numIO += idr::bitEnumContainsAny(entry, idr::Effect::io);
      numCrash += idr::bitEnumContainsAny(entry, idr::Effect::crash);
      numDiverge += idr::bitEnumContainsAny(entry, idr::Effect::diverge);
    }
    // Only facts on functions and calls changed.
    markAnalysesPreserved<SymbolTable>();
  }
};

} // namespace
