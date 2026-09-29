// Registration of the idr dialect, passes and pipeline.

#include "idr/Idr.h"

#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

using namespace mlir;

void idr::registerIdr(DialectRegistry &registry) {
  registry.insert<IdrDialect>();
}

// The pipeline's steps, in order. LLVM's own pipeline runs in idris-mlir-cc.
ArrayRef<StringRef> idr::pipelineSteps() {
  static const StringRef steps[] = {
      "idr-simplify",
      "idr-defunctionalize",
      "canonicalize",
      // A cell that never leaves its frame goes on the stack before
      // counting, which reuses only the cells of the heap. Counting runs on
      // functional code, where recursion is still a call and a match's
      // yield is its join point; every later step keeps its rule.
      "idr-stack",
      "idr-rc",
      "idr-tail-loops",
      "idr-lower",
      "canonicalize,cse",
      "convert-scf-to-cf,convert-to-llvm,reconcile-unrealized-casts",
  };
  return steps;
}

void idr::registerIdrPipeline() {
  registerIdrPasses();
  PassPipelineRegistration<>(
      "idr-pipeline", "The contract text to the LLVM dialect",
      [](OpPassManager &pm) {
        for (StringRef step : pipelineSteps())
          if (failed(parsePassPipeline(step, pm)))
            llvm::report_fatal_error("idr-pipeline: bad step");
      });
}
