// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The bottom-up SCC pipeline idr-simplify runs under --scc-pipeline, in
// three parts. The inliner already walks the call graph bottom-up by
// SCC and takes a callable only when its callees are final; this
// pipeline arranges the round's other passes around that order once,
// instead of repeating all of them until a fixpoint: the facts and
// the per-function step before it, specialization as counted delta
// iterations after it, and the module constants and dead symbols at
// the end. What the rounds discovered by repetition -- a call the
// next statement exposes, a clone a later call site wants -- the
// order and the deltas provide by construction.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Canonicalize.h"
#include "idr/Transforms/Simplify.h"

#include "mlir/Dialect/Arith/Transforms/Passes.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Passes.h"

// The passes of other areas, from the one declaration of each.
namespace idr {
#define GEN_PASS_DECL_IDREFFECTS
#define GEN_PASS_DECL_IDRIDENTITY
#define GEN_PASS_DECL_IDRREDIRECT
#define GEN_PASS_DECL_IDRINLINE
#define GEN_PASS_DECL_IDRSPECIALIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// The per-function step: what a callable needs once its callees are
// final, and again on what a delta exposed in it.
void functionStep(OpPassManager &pm) {
  OpPassManager &fn = pm.nest<idr::FuncOp>();
  fn.addPass(idr::createIdrIdentity());
  fn.addPass(idr::createCanonicalizerPass());
  fn.addPass(createCSEPass());
  fn.addPass(idr::createIdrRedirect());
}

} // namespace

void idr::buildSimplifySCCPre(OpPassManager &pm) {
  pm.addPass(createIdrEffects());
  // Constants first, once: loop-breaker marking reads the closure
  // constants SCCP finds, and in the rounds it read the previous
  // round's. The post step runs it again on what inlining exposed.
  pm.addPass(createSCCPPass());
  pm.addPass(createIdrLoopBreakers());
  // The facts the per-function step reads, computed once here; the
  // deltas' own steps read what specialization recomputes for them.
  pm.addPass(createIdrRoundFacts());
  functionStep(pm);
}

void idr::buildSimplifySCCDelta(OpPassManager &pm) {
  pm.addPass(createIdrInline());
  pm.addPass(createIdrSpecialize());
  // The facts the step reads, recomputed on what the delta changed:
  // a nested manager keeps no module analysis alive past it.
  pm.addPass(createIdrRoundFacts());
  functionStep(pm);
}

void idr::buildSimplifySCCPost(OpPassManager &pm) {
  pm.addPass(createSCCPPass());
  pm.addPass(createIdrRoundFacts());
  functionStep(pm);
  pm.nest<idr::FuncOp>().addPass(arith::createIntRangeOptimizationsPass());
  pm.addPass(createSymbolDCEPass());
}

LogicalResult idr::runSimplifySCCPipeline(
    ModuleOp module, llvm::function_ref<LogicalResult(OpPassManager &)> run,
    OpPassManager &pre, OpPassManager &delta, OpPassManager &post,
    OpPassManager &removal, unsigned limit, unsigned maxRounds, unsigned &deltas) {
  while (true) {
    if (failed(run(pre)))
      return failure();
    while (true) {
      // A delta ends when it changed nothing, by the same fingerprint
      // the removal loop judges by: clone growth alone misses the
      // inlining a delta's own canonicalization exposes (a call no
      // clone was needed to reach).
      OperationFingerPrint before(module.getOperation());
      if (failed(run(delta)))
        return failure();
      ++deltas;
      if (deltas > limit) {
        module.emitError() << "unsupported (compile-time budget): idr-simplify did not "
                              "reach a fixpoint in "
                           << maxRounds << " rounds";
        return failure();
      }
      if (OperationFingerPrint(module.getOperation()) == before)
        break;
    }
    if (failed(run(post)))
      return failure();
    OperationFingerPrint before(module.getOperation());
    if (failed(run(removal)))
      return failure();
    if (OperationFingerPrint(module.getOperation()) == before)
      return success();
  }
}
