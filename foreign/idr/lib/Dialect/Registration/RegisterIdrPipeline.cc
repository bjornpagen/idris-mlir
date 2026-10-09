// Registration of the idr passes and of the named pipeline idr-pipeline.

#include "idr/Idr.h"

#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

using namespace mlir;

void idr::registerIdrPipeline() {
  registerIdrPasses();
  PassPipelineRegistration<>(
      "idr-pipeline", "The contract text to the LLVM dialect",
      [](OpPassManager &pm) {
        for (StringRef step : pipelineSteps())
          if (failed(parsePassPipeline(step, pm)))
            llvm::reportFatalInternalError("idr-pipeline: bad step");
      });
}
