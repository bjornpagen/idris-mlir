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

// The pipeline. A group, `nest<T>()`, runs its passes over every op of kind
// T directly inside the op its manager runs on, in parallel; each group is
// a manager of its own. The program is one idr.program in the module, so
// its passes are a group on it, its functions' passes a group inside that,
// and the passes after lowering, once idr-entry has moved the program's
// functions into the module, groups on the module's func.func. LLVM's own
// pipeline runs in idris-mlir, after it. The pipeline is built before any
// program exists, so its canonicalizers have no symbol table to read a
// callee's effects in, and to them a call may do anything.
void idr::buildPipeline(mlir::OpPassManager &pm) {
  mlir::OpPassManager &program = pm.nest<idr::ProgramOp>();
  // Of each class of functions that are one function twice over, the rest
  // of the pipeline sees one, so the label sets are made over fewer
  // functions.
  program.addPass(idr::createIdrDeduplicate());
  // Before the optimizer: every closure becomes a constructor, every apply
  // a dispatch of direct calls and every force a call of its sum's
  // dispatch, so every later pass is first-order and the call graph sees
  // every call.
  program.addPass(idr::createIdrDefunctionalize());
  // Before inlining, while each continuation still returns to the one
  // place it was made for: case-of-case would copy the call of it.
  program.addPass(idr::createIdrContify());
  // Each function once, after its callees are final.
  program.addPass(idr::createIdrOptimize());
  // A tensor of records becomes its columns on the optimized bodies, before
  // the liveness analysis below, so that a column nothing reads goes with
  // the rest of what no caller reads.
  program.addPass(idr::createIdrColumns());
  // What the conversion leaves for folding: a record built from its columns'
  // elements only to be taken apart again, and a field read of it.
  {
    mlir::OpPassManager &functions = program.nest<idr::FuncOp>();
    functions.addPass(idr::createCanonicalizerPass(nullptr));
    functions.addPass(mlir::createCSEPass());
  }
  // What only a liveness analysis of the whole program removes (a
  // parameter or result no caller reads, and what feeds it), once, on the
  // optimized program. The root keeps its signature and its body: it is
  // the program's entry, the one function whose symbol is public, so both
  // passes take it to be called from outside. The removal's own
  // canonicalization is off: it folds region-branch patterns on the
  // matches alone, and a field one of them folds leaves the constructor it
  // read dead but in place, still holding a world or a linear value that
  // the fold's user now holds too. symbol-dce then takes the functions
  // nothing names any more. With its canonicalization off the pass runs no
  // greedy driver: its liveness is a solve to the fixed point of a
  // two-valued lattice and its cleanup one walk. On, a rewrite not
  // converged after ten rounds would fail the pass, and a count would
  // refuse the program.
  mlir::RemoveDeadValuesPassOptions dead;
  dead.canonicalize = false;
  program.addPass(mlir::createRemoveDeadValuesPass(dead));
  program.addPass(mlir::createSymbolDCEPass());
  // The arrays stage, on final bodies: inlining has already put together
  // what it will and every callee's effects are final. Each array op becomes
  // a linalg op or its ordered loop nest.
  program.nest<idr::FuncOp>().addPass(idr::createIdrStructureLoops());
  // Before counting, which sees buffers and needs no model of tensors. It
  // eliminates empty tensors itself, on its own module analysis.
  program.addPass(idr::createIdrBufferize());
  {
    mlir::OpPassManager &functions = program.nest<idr::FuncOp>();
    functions.addPass(idr::createCanonicalizerPass(nullptr));
    functions.addPass(mlir::createCSEPass());
  }
  // A cell that never leaves its frame goes on the stack before counting,
  // which reuses only the cells of the heap. Counting runs on functional
  // code, where recursion is still a call and a match's yield is its join
  // point; every later pass keeps its rule.
  program.addPass(idr::createIdrStack());
  // While a self call's result is still the operand of the addition a tail
  // returns. Counting borrows that result and drops it after the addition,
  // and the call would no longer be the tail.
  program.addPass(idr::createIdrAccumulate());
  program.addPass(idr::createIdrRc());
  // On the grades counting wrote: the promise the program's types make.
  program.addPass(idr::createIdrDemand());
  program.addPass(idr::createIdrTrmc());
  program.nest<idr::FuncOp>().addPass(idr::createIdrTailLoops());
  // On loops, which it versions, and after counting, whose counts of the
  // bigs it proves small it removes.
  program.addPass(idr::createIdrNarrow());
  // On the module, which the program leaves: the lowering converts the
  // program's functions where they are, and idr-entry moves them into the
  // module, makes the program's root its entry, @main, and erases the
  // program.
  pm.addPass(idr::createIdrLower());
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
    // Upstream's lowering passes here (convert-linalg-to-loops,
    // convert-vector-to-scf, expand-strided-metadata and the pre-lowering
    // of convert-vector-to-llvm) run the greedy driver at its default of
    // ten rounds and ignore whether it converged. No program's acceptance
    // rests on that count. Each of their patterns that removes an op a
    // later conversion cannot take (a linalg op on buffers; a transfer of
    // rank above one; a subview, expand_shape or collapse_shape; an n-D
    // broadcast, shape cast, transpose, mask or strided slice) decides on
    // that op alone, a transfer also on the buffer its own preparation
    // made. The driver's first round visits every op there is, and every
    // op a rewrite creates or modifies joins that round, so the first round
    // lowers them all: a spent count leaves only later rounds' folds and
    // clean-ups undone.
    lowered.addPass(mlir::createConvertLinalgToLoopsPass());
    lowered.addPass(idr::createCanonicalizerPass(nullptr));
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
    lowered.addPass(idr::createCanonicalizerPass(nullptr));
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
