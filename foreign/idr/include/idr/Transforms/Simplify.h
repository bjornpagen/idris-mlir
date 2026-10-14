// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The simplify loop, the round it repeats, and the passes only it runs
// (loop breakers, the round's facts) or that prepare for it (contify).
#ifndef IDR_TRANSFORMS_SIMPLIFY_H
#define IDR_TRANSFORMS_SIMPLIFY_H

#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "mlir/Pass/PassManager.h"

#include <memory>

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
// per-function step that reads the clones it made), and what runs
// once after the deltas stop (constants, the per-function step,
// symbol DCE). idr-simplify loops the delta while it makes clones.
void buildSimplifySCCPre(mlir::OpPassManager &pm);
void buildSimplifySCCDelta(mlir::OpPassManager &pm);
void buildSimplifySCCPost(mlir::OpPassManager &pm);

// The instrumentation that counts, times and traces the rounds of every
// idr-simplify the manager runs, and reports their statistics. The
// manager's owner adds it; idr-simplify fails under a manager without it.
std::unique_ptr<mlir::PassInstrumentation> createSimplifyInstrumentation();

} // namespace idr

#endif // IDR_TRANSFORMS_SIMPLIFY_H
