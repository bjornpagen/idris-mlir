// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-in-bounds: every guard that can never crash is erased. The module's
// Lengths is computed first, so that the proofs, nested per function, find
// it and the SymbolTable cached on the module; the pass counts the guards
// before and after, since the nested proofs keep no statistics of their
// own.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/Ranges.h"
#include "idr/Transforms/InBounds.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"

namespace idr {
#define GEN_PASS_DEF_IDRINBOUNDS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

unsigned guardsIn(ModuleOp module) {
  unsigned count = 0;
  module.walk([&](idr::GuardOpInterface) { ++count; });
  return count;
}

struct InBounds : idr::impl::IdrInBoundsBase<InBounds> {
  using IdrInBoundsBase::IdrInBoundsBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    if (!getAnalysis<idr::Ranges>().valid()) {
      module.emitError("internal error: idr-in-bounds: the range analysis failed");
      return signalPassFailure();
    }
    // Computed here and left cached for the nested proofs; neither is held
    // across the nested run, which leaves no module analysis behind it.
    getAnalysis<SymbolTable>();
    getAnalysis<idr::inbounds::Lengths>();
    unsigned before = guardsIn(module);
    OpPassManager pm(ModuleOp::getOperationName());
    pm.nest<idr::FuncOp>().addPass(idr::inbounds::createProveInBoundsPass());
    if (failed(runPipeline(pm, module)))
      return signalPassFailure();
    unsigned after = guardsIn(module);
    numProved += before - after;
    numChecked += after;
    if (before == after)
      return markAllAnalysesPreserved();
    // A guard is no symbol, names none and declares nothing.
    markAnalysesPreserved<idr::Holds, idr::TypeGraph, idr::Layouts, SymbolTable>();
  }
};

} // namespace
