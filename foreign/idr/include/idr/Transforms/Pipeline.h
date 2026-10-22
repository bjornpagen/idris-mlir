// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's passes and idris-mlir's pipeline: the base every pass with
// a stage derives from, every pass's constructor and their registration,
// all printed from the specification's one list (Spec.Pipeline), and the
// pipeline built from that list, whole or between two stages.
#ifndef IDR_TRANSFORMS_PIPELINE_H
#define IDR_TRANSFORMS_PIPELINE_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

#include <type_traits>

namespace idr {

// The base of every pass whose record names the stage it requires,
// `Requires`, and the one it leaves, `Sets`: the record's printed
// baseClass, inside which upstream's generator names the pass `DerivedT`,
// so the base calls the pass's own body with no virtual. It finds the
// program the pass runs on (the anchor, the program around it, or the one
// program of a module), refuses a program at another stage, runs the pass
// on it (DerivedT::runOnProgram, handed the program it found), and leaves
// the program at `Sets` unless the pass failed. A pass that runs at any
// stage derives from upstream's base instead.
template <typename DerivedT, typename OpT, Stage Requires, Stage Sets>
class StagedPass : public mlir::OperationPass<OpT> {
  // A function pass runs beside its siblings, which read the program's
  // stage; only a pass on the program or on the module may change it. The
  // specification's pipeline type refuses the case before any C++ exists;
  // this states the same of the class.
  static_assert(Requires == Sets || std::is_same_v<OpT, ProgramOp> ||
                    std::is_same_v<OpT, mlir::ModuleOp>,
                "a pass on a function leaves the stage it found");

protected:
  explicit StagedPass(mlir::TypeID passID) : mlir::OperationPass<OpT>(passID) {}
  StagedPass(const StagedPass &) = default;

private:
  void runOnOperation() final {
    OpT anchor = this->getOperation();
    ProgramOp program;
    if constexpr (std::is_same_v<OpT, ProgramOp>) {
      program = anchor;
    } else if constexpr (std::is_same_v<OpT, mlir::ModuleOp>) {
      // A module may hold any number of programs, as MLIR sees it; the
      // pass runs on its one.
      auto programs = anchor.template getOps<ProgramOp>();
      if (!llvm::hasSingleElement(programs)) {
        anchor.emitError("internal error: ")
            << this->getArgument() << " runs on a module that holds one program, not "
            << llvm::range_size(programs);
        return this->signalPassFailure();
      }
      program = *programs.begin();
    } else {
      program = llvm::cast<ProgramOp>(anchor->getParentOp());
    }
    if (program.getStage() != Requires) {
      anchor->emitError("internal error: ")
          << this->getArgument() << " runs on a program at " << stringifyStage(Requires)
          << ", not " << stringifyStage(program.getStage());
      return this->signalPassFailure();
    }
    static_cast<DerivedT &>(*this).runOnProgram(program);
    if constexpr (Requires != Sets)
      if (!this->getPassState().irAndPassFailed.getInt())
        program.setStage(Sets);
  }
};

} // namespace idr

// Every pass is declared once, by its library's header; registration
// needs every one.
#include "idr/Conversion/Passes.h"
#include "idr/Target/Target.h"
#include "idr/Transforms/Bufferize.h"
#include "idr/Transforms/Columns.h"
#include "idr/Transforms/Counting.h"
#include "idr/Transforms/Deduplicate.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Expect.h"
#include "idr/Transforms/InPlace.h"
#include "idr/Transforms/Inline.h"
#include "idr/Transforms/Lifetimes.h"
#include "idr/Transforms/Narrow.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Ownership.h"
#include "idr/Transforms/StructureLoops.h"
#include "idr/Transforms/Tail.h"

namespace idr {

#define GEN_PASS_REGISTRATION
#include "idr/Transforms/Passes.h.inc"

// idris-mlir's pipeline into `pm`, a manager on the builtin.module that
// holds the program: every step whose stages lie between `from` and `to`,
// in the specification's order, the whole pipeline from `higher` to
// `lowered`. Never idr-target: the driver runs it first.
void buildPipeline(mlir::OpPassManager &pm, Stage from = Stage::Higher,
                   Stage to = Stage::Lowered);

// Registers the pipeline with the pass registry: --idr-pipeline, its
// options the stages it runs between.
void registerIdrPipeline();

// The schedule's interpreter, given the library's entry point: the one
// upstream pass the pipeline configures.
std::unique_ptr<mlir::Pass> scheduleInterpreter();

} // namespace idr

#endif // IDR_TRANSFORMS_PIPELINE_H
