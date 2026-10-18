// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's passes and idris-mlir's pipelines: the base every pass
// with a stage derives from, every idr pass's constructor and their
// registration, from the one .td, and the pipelines built from those
// constructors.
#ifndef IDR_TRANSFORMS_PIPELINE_H
#define IDR_TRANSFORMS_PIPELINE_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

#include <type_traits>

namespace idr {

// The base of every pass whose record (Passes.td) names the stage it
// requires, `Requires`, and the one it leaves, `Sets`: PassBase's
// baseClass, from which upstream's generator derives the pass's own base,
// so that the pass checks its stage in every tool that runs it. It finds
// the program the pass runs on (the anchor, the program around it, or the
// one program of a module), refuses a program at another stage, runs the
// pass on it (runOnProgram, handed the program it found), and leaves the
// program at `Sets` unless the pass failed. A pass that runs at any stage
// derives from upstream's base instead.
template <typename OpT, Stage Requires, Stage Sets>
class StagedPass : public mlir::OperationPass<OpT> {
  // A function pass runs beside its siblings, which read the program's
  // stage; only a pass on the program or on the module may change it.
  static_assert(Requires == Sets || std::is_same_v<OpT, ProgramOp> ||
                    std::is_same_v<OpT, mlir::ModuleOp>,
                "a pass on a function leaves the stage it found");

protected:
  explicit StagedPass(mlir::TypeID passID) : mlir::OperationPass<OpT>(passID) {}
  StagedPass(const StagedPass &) = default;

  // The pass's body, on `program`, at `Requires`: the anchor, the program
  // around it, or the module's one program.
  virtual void runOnProgram(ProgramOp program) = 0;

private:
  void runOnOperation() final {
    OpT anchor = this->getOperation();
    ProgramOp program;
    if constexpr (std::is_same_v<OpT, ProgramOp>) {
      program = anchor;
    } else if constexpr (std::is_same_v<OpT, mlir::ModuleOp>) {
      // A module may hold any number of programs, as MLIR sees it; the
      // pass runs on one.
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
    runOnProgram(program);
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
#include "idr/Transforms/Deduplicate.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/Demand.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Expect.h"
#include "idr/Transforms/Identity.h"
#include "idr/Transforms/Narrow.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Ownership.h"
#include "idr/Transforms/Specialize.h"
#include "idr/Transforms/Stack.h"
#include "idr/Transforms/StructureLoops.h"
#include "idr/Transforms/Tail.h"

namespace idr {

#define GEN_PASS_REGISTRATION
#include "idr/Transforms/Passes.h.inc"

// idris-mlir's pipeline, idr-deduplicate to idr-tail-calls, into `pm`, a
// manager on the builtin.module that holds the program: the program's
// passes nested on its idr.program, the rest on the module once idr-entry
// has taken the program apart. Never idr-target: the driver runs it first,
// and idris-mlir-opt runs it by name.
void buildPipeline(mlir::OpPassManager &pm);

// Registers the pipelines with the pass registry: --idr-pipeline, and
// --idr-rc, the steps that make every reference explicit.
void registerIdrPipeline();

} // namespace idr

#endif // IDR_TRANSFORMS_PIPELINE_H
