// idris-mlir-opt: mlir-opt with the idr dialect, passes and pipeline
// registered. Like idris-mlir, it runs on the runtime's reserved-stack
// runner, on a stack of 2^40 bytes, so the nested constants MLIR's parser
// and printer recurse over are bounded by memory, not by the process's
// stack. PIN(mlir-recursion)

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Profile.h"
#include "idr/Transforms/Pipeline.h"
#include "idr/Transforms/Simplify.h"

#include "idris_rt.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/FileUtilities.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/raw_ostream.h"

#include <cstddef>
#include <memory>
#include <string>

#include <unistd.h>

namespace {

struct Invocation {
  int argc;
  char **argv;
  int status = 1;
};

void optMain(void *argument) {
  auto &invocation = *static_cast<Invocation *>(argument);
  llvm::InitLLVM init(invocation.argc, invocation.argv);
  mlir::registerAllPasses();
  idr::registerIdrPasses();
  idr::registerIdrPipeline();
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  registry.insert<idr::IdrDialect>();
  auto [inputPath, outputPath] = mlir::registerAndParseCLIOptions(
      invocation.argc, invocation.argv, "idris-mlir-opt: the idr dialect\n", registry);
  // idr-simplify counts its rounds through an instrumentation of the manager
  // that runs it, so every manager this tool runs carries one, ahead of the
  // pipeline the command line gives, and the profile's zones, as
  // idris-mlir's manager does.
  mlir::MlirOptMainConfig config = mlir::MlirOptMainConfig::createFromCLOptions();
  config.setPassPipelineSetupFn([parsed = config](mlir::PassManager &pm) {
    pm.addInstrumentation(idr::createSimplifyInstrumentation());
    idr::profile::addInstrumentation(pm);
    return parsed.setupPassPipeline(pm);
  });
  // MlirOptMain answers these before it reads any input, which then need not
  // exist.
  if (config.shouldShowDialects() || config.shouldListPasses()) {
    invocation.status = mlir::failed(mlir::MlirOptMain(llvm::outs(), nullptr, registry, config));
    return;
  }
  std::string error;
  std::unique_ptr<llvm::MemoryBuffer> input = mlir::openInputFile(inputPath, &error);
  if (!input) {
    llvm::errs() << error << "\n";
    return;
  }
  std::unique_ptr<llvm::ToolOutputFile> output = mlir::openOutputFile(outputPath, &error);
  if (!output) {
    llvm::errs() << error << "\n";
    return;
  }
  if (mlir::failed(mlir::MlirOptMain(output->os(), std::move(input), registry, config)))
    return;
  output->keep();
  invocation.status = 0;
}

// From the fault handler: only write and _exit.
[[noreturn]] void exhausted() {
  static constexpr char message[] = "idris-mlir-opt: the stack is exhausted\n";
  (void)!write(2, message, sizeof message - 1);
  _exit(1);
}

} // namespace

int main(int argc, char **argv) {
  Invocation invocation{argc, argv};
  if (idris_rt_run_on_stack(optMain, &invocation, size_t{1} << 40, size_t{1} << 20,
                            exhausted) != 0) {
    static constexpr char message[] = "idris-mlir-opt: no stack could be reserved\n";
    (void)!write(2, message, sizeof message - 1);
    return 1;
  }
  return invocation.status;
}
