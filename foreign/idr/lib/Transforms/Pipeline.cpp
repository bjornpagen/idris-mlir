// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir's pipeline, from the idr dialect to the LLVM dialect, written
// once as a sequence of constructor calls. Nothing chooses among passes:
// every program runs every one, so what one compilation runs is what the
// tests run.

#include "idr/IR/IdrDialect.h"
#include "idr/Target/Target.h"
#include "idr/Transforms/Canonicalize.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Conversion/Passes.h"
#include "mlir/Dialect/Bufferization/Transforms/Passes.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Linalg/Passes.h"
#include "mlir/Dialect/MemRef/Transforms/Passes.h"
#include "mlir/Dialect/Transform/Transforms/Passes.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/Passes.h"

// The pipeline. A group, `pm.nest<T>()`, runs its passes over every op of
// kind T directly inside the module, in parallel; each group is a manager
// of its own. LLVM's own pipeline runs in idris-mlir, after it.
void idr::buildPipeline(mlir::OpPassManager &pm) {
  // Of each class of functions that are one function twice over, the rest
  // of the pipeline sees one, so the label sets are made over fewer
  // functions.
  pm.addPass(idr::createIdrDeduplicate());
  // Before the optimizer: every closure becomes a constructor and every
  // apply a dispatch of direct calls, so every later pass is first-order
  // and the call graph sees every call.
  pm.addPass(idr::createIdrDefunctionalize());
  // Before inlining, while each continuation still returns to the one
  // place it was made for: case-of-case would copy the call of it.
  pm.addPass(idr::createIdrContify());
  // Each function once, after its callees are final.
  pm.addPass(idr::createIdrOptimize());
  // What only a module liveness analysis removes (a parameter or result no
  // caller reads, and what feeds it), once, on the optimized module. The
  // removal's own canonicalization is off: it folds region-branch patterns
  // on the matches alone, and a field one of them folds leaves the
  // constructor it read dead but in place, still holding a world or a
  // linear value that the fold's user now holds too. symbol-dce then takes
  // the functions nothing names any more.
  mlir::RemoveDeadValuesPassOptions dead;
  dead.canonicalize = false;
  pm.addPass(mlir::createRemoveDeadValuesPass(dead));
  pm.addPass(mlir::createSymbolDCEPass());
  // The arrays stage, on final bodies: inlining has already put together
  // what it will, every call's effects are final, and the loops are still
  // the scf loops dead-value removal trims. Each pure loop over a tensor
  // becomes a linalg op.
  pm.nest<idr::FuncOp>().addPass(idr::createIdrStructureLoops());
  // On the module: only there does the analysis see function boundaries.
  pm.addPass(mlir::bufferization::createEmptyTensorEliminationPass());
  // Before counting, which sees buffers and needs no model of tensors.
  pm.addPass(idr::createIdrBufferize());
  {
    mlir::OpPassManager &functions = pm.nest<idr::FuncOp>();
    functions.addPass(idr::createCanonicalizerPass());
    functions.addPass(mlir::createCSEPass());
  }
  // A cell that never leaves its frame goes on the stack before counting,
  // which reuses only the cells of the heap. Counting runs on functional
  // code, where recursion is still a call and a match's yield is its join
  // point; every later pass keeps its rule.
  pm.addPass(idr::createIdrStack());
  // While a self call's result is still the operand of the addition a tail
  // returns. Counting borrows that result and drops it after the addition,
  // and the call would no longer be the tail.
  pm.addPass(idr::createIdrAccumulate());
  pm.addPass(idr::createIdrRc());
  // On the grades counting wrote: the promise the program's types make.
  pm.addPass(idr::createIdrDemand());
  pm.addPass(idr::createIdrTrmc());
  pm.nest<idr::FuncOp>().addPass(idr::createIdrTailLoops());
  // On loops, which it versions, and after counting, whose counts of the
  // bigs it proves small it removes.
  pm.addPass(idr::createIdrNarrow());
  pm.addPass(idr::createIdrLower());
  // The lowered root becomes the program's entry, @main.
  pm.addPass(idr::createIdrEntry());
  // The loops over arrays are linalg ops after lowering: the vectorization
  // schedule computes each on the target's lanes, and upstream makes the
  // loops of those left. On the vectorized loops, the integer lanes of
  // each compute in 32 bits under a bound on the sizes, the 64-bit loop
  // kept for the sizes above it.
  {
    mlir::OpPassManager &lowered = pm.nest<mlir::func::FuncOp>();
    mlir::transform::InterpreterPassOptions schedule;
    schedule.entryPoint = idr::target::vectorizeSchedule.str();
    lowered.addPass(mlir::transform::createInterpreterPass(schedule));
    lowered.addPass(idr::createIdrNarrowLanes());
    lowered.addPass(mlir::createConvertLinalgToLoopsPass());
    lowered.addPass(idr::createCanonicalizerPass());
    lowered.addPass(mlir::createCSEPass());
  }
  // On lowered code, where a threaded value given back is its argument
  // component by component; a join that then yields the same value on
  // every path folds after it.
  pm.addPass(idr::createIdrReturnedArguments());
  // The tiles' transfers of a rank above one become loops over 1-D ones;
  // the views become offsets, the offset of a view of a view the affine
  // arithmetic of both, before the affine ops lower with the loops' bounds.
  // Each of these reads one function, so they run over the functions in
  // parallel.
  {
    mlir::OpPassManager &lowered = pm.nest<mlir::func::FuncOp>();
    lowered.addPass(idr::createCanonicalizerPass());
    lowered.addPass(mlir::createCSEPass());
    lowered.addPass(mlir::createConvertVectorToSCFPass());
    lowered.addPass(mlir::memref::createExpandStridedMetadataPass());
    lowered.addPass(mlir::createLowerAffinePass());
    lowered.addPass(mlir::createSCFToControlFlowPass());
  }
  // The vector ops then take the vector dialect's own conversion, whose
  // pre-lowering (transfers to loads and stores, steps, broadcasts, shape
  // casts) convert-to-llvm does not carry.
  pm.addPass(mlir::createConvertVectorToLLVMPass());
  pm.addPass(mlir::createConvertToLLVMPass());
  pm.addPass(mlir::createReconcileUnrealizedCastsPass());
  // On the final control flow, where a call's path to the return is what
  // LLVM sees.
  pm.addPass(idr::createIdrTailCalls());
}

void idr::registerIdrPipeline() {
  mlir::PassPipelineRegistration<>(
      "idr-pipeline", "idris-mlir's pipeline, the idr dialect to the LLVM dialect",
      [](mlir::OpPassManager &pm) { buildPipeline(pm); });
}
