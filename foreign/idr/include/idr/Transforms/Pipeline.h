// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's passes and idris-mlir's pipeline: every pass's constructor
// and their registration, printed from the specification's one list
// (Spec.Pipeline), and the pipeline built from that list, whole or between
// two stages. The base every pass with a stage derives from is the
// dialect's header's, which every pass's unit reaches.
#ifndef IDR_TRANSFORMS_PIPELINE_H
#define IDR_TRANSFORMS_PIPELINE_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

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
#include "idr/Transforms/StructureLoops.h"
#include "idr/Transforms/Tail.h"

namespace idr {

#define GEN_PASS_REGISTRATION
#include "idr/Transforms/Passes.h.inc"

// idris-mlir's pipeline into `pm`, a manager on the builtin.module that
// holds the program: idr-target first, whatever the slice, then every step
// whose stages lie between `from` and `to`, in the specification's order,
// the whole pipeline from `higher` to `lowered`.
void buildPipeline(mlir::OpPassManager &pm, Stage from = Stage::Higher,
                   Stage to = Stage::Lowered);

// Registers the pipeline with the pass registry: --idr-pipeline, its
// options the stages it runs between.
void registerIdrPipeline();

// Registers every upstream pass the pipeline runs, from its one list, and
// no other.
void registerUpstreamPasses();

// The schedule's interpreter, given the library's entry point: the one
// upstream pass the pipeline configures.
std::unique_ptr<mlir::Pass> scheduleInterpreter();

namespace pipeline {
// The steps around a nest of function passes that add atoms to rows: every
// function's and call's row given at least `atoms` before the nest, and
// every row written equal to its derivation after it.
std::unique_ptr<mlir::Pass> createWidenRows(effects::Row atoms);
std::unique_ptr<mlir::Pass> createWriteRows();
} // namespace pipeline

} // namespace idr

#endif // IDR_TRANSFORMS_PIPELINE_H
