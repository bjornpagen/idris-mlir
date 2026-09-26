// Registration of the idr dialect, passes and pipeline (DRV-OPT-1, OPT-PIPE-1).

#include "idr/Idr.h"

#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

using namespace mlir;

void idr::registerIdr(DialectRegistry &registry) {
  registry.insert<IdrDialect>();
}

// OPT-PIPE-1, steps 1-11. Step 11 (LLVM) happens in idris-mlir-cc.
ArrayRef<StringRef> idr::pipelineSteps() {
  static const StringRef steps[] = {
      "idr-check-input",
      "idr-entry",
      "inline",
      // After inlining: specializations of monadic code often become self
      // recursive only once their helpers are inlined (OPT-PIPE-2).
      "idr-tail-loops",
      "sccp",
      "canonicalize",
      "cse",
      "symbol-dce",
      "idr-lower",
      "canonicalize,cse",
      "convert-scf-to-cf,convert-to-llvm,reconcile-unrealized-casts",
  };
  return steps;
}

void idr::registerIdrPipeline() {
  registerIdrPasses();
  PassPipelineRegistration<>(
      "idr-pipeline", "OPT-PIPE-1 steps 1-10: contract text to the LLVM dialect",
      [](OpPassManager &pm) {
        for (StringRef step : pipelineSteps())
          if (failed(parsePassPipeline(step, pm)))
            llvm::report_fatal_error("idr-pipeline: bad step");
      });
}
