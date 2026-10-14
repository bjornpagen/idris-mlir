// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The simplify loop, the round it repeats, and the passes only it runs
// (loop breakers, the round's facts) or that prepare for it (contify).
#ifndef IDR_TRANSFORMS_SIMPLIFY_H
#define IDR_TRANSFORMS_SIMPLIFY_H

#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "mlir/Pass/PassManager.h"

#include "llvm/ADT/STLExtras.h"

#include <chrono>
#include <cstdint>
#include <map>
#include <memory>
#include <string>

namespace idr {

#define GEN_PASS_DECL_IDRSIMPLIFY
#define GEN_PASS_DECL_IDRROUNDFACTS
#define GEN_PASS_DECL_IDRLOOPBREAKERS
#define GEN_PASS_DECL_IDRCONTIFY
#include "idr/Transforms/Passes.h.inc"

// Adds the passes of one round of idr-simplify to `pm`, anchored on
// builtin.module, in order.
void buildSimplifyRound(mlir::OpPassManager &pm);

// The bottom-up SCC pipeline in three parts: what runs once before
// inlining (effects, constants, loop breakers, the facts, the
// per-function step), one delta iteration (inline, specialize, the
// per-function step on what it exposed), and what runs once after
// the deltas stop (constants, the per-function step, symbol DCE).
void buildSimplifySCCPre(mlir::OpPassManager &pm);
void buildSimplifySCCDelta(mlir::OpPassManager &pm);
void buildSimplifySCCPost(mlir::OpPassManager &pm);

// Runs the SCC pipeline on `module`: the pre part once, the delta
// until one changes nothing (the structural fingerprint decides, as
// it decides a round's fixpoint), the post part once, then the
// removal; a removal that changed the module resumes the pipeline on
// what it exposed. `run` runs one part under the caller's pass
// manager. `deltas` counts the deltas run, in and out; more than
// `limit` of them is the budget error `maxRounds` names.
mlir::LogicalResult
runSimplifySCCPipeline(mlir::ModuleOp module,
                       llvm::function_ref<mlir::LogicalResult(mlir::OpPassManager &)> run,
                       mlir::OpPassManager &pre, mlir::OpPassManager &delta,
                       mlir::OpPassManager &post, mlir::OpPassManager &removal,
                       unsigned limit, unsigned maxRounds, unsigned &deltas);

// What the module holds after a round.
struct SimplifyCensus {
  unsigned functions = 0, clones = 0;
  uint64_t ops = 0;
};

SimplifyCensus takeSimplifyCensus(mlir::ModuleOp module);

// The remark after round `round`: what the module holds, and how
// long the round took. The census is taken only for a remark
// someone reads.
void traceSimplifyRound(mlir::ModuleOp module, unsigned round,
                        std::chrono::steady_clock::duration took,
                        llvm::function_ref<const SimplifyCensus &()> census);

// The statistics of the round's passes, summed by
// `<pass>.<statistic>`, as one remark.
void reportSimplifyStatistics(mlir::ModuleOp module,
                              const std::map<std::string, uint64_t> &totals);

// The instrumentation that counts, times and traces the rounds of every
// idr-simplify the manager runs, and reports their statistics. The
// manager's owner adds it; idr-simplify fails under a manager without it.
std::unique_ptr<mlir::PassInstrumentation> createSimplifyInstrumentation();

} // namespace idr

#endif // IDR_TRANSFORMS_SIMPLIFY_H
