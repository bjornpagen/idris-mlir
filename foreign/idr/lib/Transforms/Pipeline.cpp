// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir's pipeline, from the idr dialect to the LLVM dialect, read from
// the specification's one list (Spec.Pipeline), printed as a table of steps
// each with the stages it runs between. Nothing chooses among passes: every
// program runs every step, so what a compilation runs is what the tests
// run; a test runs a slice between two stages of the same table.

#include "idr/Transforms/Pipeline.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Target/Target.h"
#include "idr/Transforms/Effects.h"

#include "mlir/Conversion/Passes.h"
#include "mlir/Dialect/LLVMIR/Transforms/Passes.h"
#include "mlir/Dialect/Linalg/Passes.h"
#include "mlir/Dialect/MemRef/Transforms/Passes.h"
#include "mlir/Dialect/Transform/Transforms/Passes.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/Passes.h"

#include "idr/IR/Generated/Pipeline.h.inc"

namespace idr {
#define GEN_PASS_DEF_IDRWIDENROWS
#define GEN_PASS_DEF_IDRWRITEROWS
#include "idr/Transforms/InnerPasses.h.inc"
} // namespace idr

std::unique_ptr<mlir::Pass> idr::scheduleInterpreter() {
  mlir::transform::InterpreterPassOptions schedule;
  schedule.entryPoint = idr::target::vectorizeSchedule.str();
  return mlir::transform::createInterpreterPass(schedule);
}

namespace {

// The atoms the nest after it may add, read from the passes' records; the
// widening changes no op and keeps every analysis.
struct WidenRows : idr::impl::IdrWidenRowsBase<WidenRows> {
  explicit WidenRows(idr::effects::Row atoms) : atoms(atoms) {}

  void runOnOperation() override {
    idr::rows::widen(getOperation(), atoms);
    markAllAnalysesPreserved();
  }

  idr::effects::Row atoms;
};

// The one writer of rows over the program graph, which it keeps, its work
// the pass's.
struct WriteRows : idr::impl::IdrWriteRowsBase<WriteRows> {
  void runOnOperation() override {
    idr::solver::Work work;
    idr::rows::write(getOperation(), getAnalysis<idr::solver::ProgramGraph>(), work);
    numWork += work.steps();
    markAnalysesPreserved<idr::solver::ProgramGraph>();
  }
};

} // namespace

std::unique_ptr<mlir::Pass> idr::pipeline::createWidenRows(effects::Row atoms) {
  return std::make_unique<WidenRows>(atoms);
}

std::unique_ptr<mlir::Pass> idr::pipeline::createWriteRows() {
  return std::make_unique<WriteRows>();
}

// A step runs when the stages it runs between lie within the slice asked
// for: the whole pipeline is the slice from higher to lowered.
void idr::buildPipeline(mlir::OpPassManager &pm, Stage from, Stage to) {
  for (const pipeline::Step &step : pipeline::steps)
    if (from <= step.at && step.after <= to)
      step.add(pm);
}

namespace {

// The stages a slice of the pipeline runs between, read by their printed
// names, the values printed from the specification's stages.
struct Slice : mlir::PassPipelineOptions<Slice> {
  Option<idr::Stage> from{*this, "from", llvm::cl::desc("The stage the slice starts at"),
                          llvm::cl::init(idr::Stage::Higher), llvm::cl::values(IDR_STAGE_OPTION_VALUES)};
  Option<idr::Stage> to{*this, "to", llvm::cl::desc("The stage the slice ends at"),
                        llvm::cl::init(idr::Stage::Lowered), llvm::cl::values(IDR_STAGE_OPTION_VALUES)};
};

} // namespace

void idr::registerUpstreamPasses() { pipeline::registerUpstream(); }

void idr::registerIdrPipeline() {
  mlir::PassPipelineRegistration<Slice>(
      "idr-pipeline", "idris-mlir's pipeline, the idr dialect to the LLVM dialect, or a slice of it",
      [](mlir::OpPassManager &pm, const Slice &slice) { buildPipeline(pm, slice.from, slice.to); });
}
