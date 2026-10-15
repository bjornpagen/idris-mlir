// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's passes and idris-mlir's pipeline: every idr pass's
// constructor and their registration, from the one .td, and the one
// pipeline built from those constructors.
#ifndef IDR_TRANSFORMS_PIPELINE_H
#define IDR_TRANSFORMS_PIPELINE_H

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

#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

namespace idr {

#define GEN_PASS_REGISTRATION
#include "idr/Transforms/Passes.h.inc"

// idris-mlir's pipeline, idr-deduplicate to idr-tail-calls, into `pm`, a
// manager on the builtin.module that holds the program: the program's
// passes nested on its idr.program, the rest on the module once idr-entry
// has taken the program apart. Never idr-target: the driver runs it first,
// and idris-mlir-opt runs it by name.
void buildPipeline(mlir::OpPassManager &pm);

// Registers --idr-pipeline with the pass registry.
void registerIdrPipeline();

} // namespace idr

#endif // IDR_TRANSFORMS_PIPELINE_H
