// The dialect's passes and idris-mlir's pipeline: every idr pass's
// constructor and their registration, from the one .td, and the pipeline
// built from those constructors.
#ifndef IDR_TRANSFORMS_PIPELINE_H
#define IDR_TRANSFORMS_PIPELINE_H

// Every pass is declared once, by its library's header; registration
// needs every one.
#include "idr/Conversion/Passes.h"
#include "idr/Target/Target.h"
#include "idr/Transforms/Defunctionalize.h"
#include "idr/Transforms/Demand.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Expect.h"
#include "idr/Transforms/Identity.h"
#include "idr/Transforms/InBounds.h"
#include "idr/Transforms/Inline.h"
#include "idr/Transforms/Isolate.h"
#include "idr/Transforms/Narrow.h"
#include "idr/Transforms/Ownership.h"
#include "idr/Transforms/Simplify.h"
#include "idr/Transforms/Specialize.h"
#include "idr/Transforms/Stack.h"
#include "idr/Transforms/Tail.h"
#include "idr/Transforms/Vectorize.h"

#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

#include "llvm/ADT/StringSet.h"

#include <string>
#include <vector>

namespace idr {

#define GEN_PASS_REGISTRATION
#include "idr/Transforms/Passes.h.inc"

// What the driver decides about the pipeline: the passes left out by
// argument, with idr-rc's reuse and sink and idr-demand's in-place, which
// are not passes but are turned off the same way; and whether idr-demand
// checks the in-place promise.
struct PipelineOptions {
  llvm::StringSet<> without;
  bool demandInPlace = false;
};

// idris-mlir's pipeline, idr-isolate to idr-tail-calls, into `pm`, a
// manager on builtin.module. Never idr-target: the driver runs it first,
// and idris-mlir-opt runs it by name.
void buildPipeline(mlir::OpPassManager &pm, const PipelineOptions &options);

// The argument of every pass buildPipeline adds with no options, nested
// ones included, in order: what --without may name.
std::vector<std::string> pipelinePassNames();

// Registers --idr-pipeline with the pass registry.
void registerIdrPipeline();

} // namespace idr

#endif // IDR_TRANSFORMS_PIPELINE_H
