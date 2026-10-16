// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir-opt: mlir-opt with the idr dialect, passes and pipeline
// registered. Like idris-mlir, it runs on the runtime's reserved-stack
// runner, on the tools' stack, so the nested constants MLIR's parser and
// printer recurse over are bounded by memory, not by the process's stack.
// PIN(mlir-recursion)

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Profile.h"
#include "idr/Support/Stack.h"
#include "idr/Target/Target.h"
#include "idr/Transforms/Contracts.h"
#include "idr/Transforms/Pipeline.h"

#include "idris_rt.h"

#include "mlir/IR/DialectRegistry.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/FileUtilities.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

#include "llvm/Support/CommandLine.h"
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

// A test's check of every pass as it runs, never a choice of how a program is compiled.
llvm::cl::opt<bool> contracts(
    "idr-contracts",
    llvm::cl::desc("Check after every pass on the module or the program the relations it must "
                   "keep, and fail naming the pass that broke one"),
    llvm::cl::init(false));

void optMain(void *argument) {
  auto &invocation = *static_cast<Invocation *>(argument);
  llvm::InitLLVM init(invocation.argc, invocation.argv);
  mlir::registerAllPasses();
  idr::registerIdrPasses();
  idr::registerIdrPipeline();
  idr::registerContractTestPass();
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  registry.insert<idr::IdrDialect>();
  // How a closure moves through the upstream ops that can hold one, and
  // the schedules the pipeline's interpreter runs, loaded with the
  // transform dialect, in every context made from this registry.
  idr::registerFlowInterfaceExternalModels(registry);
  idr::target::registerScheduleLibrary(registry);
  auto [inputPath, outputPath] = mlir::registerAndParseCLIOptions(
      invocation.argc, invocation.argv, "idris-mlir-opt: the idr dialect\n", registry);
  // --time-trace, when it named a file: written as this returns.
  idr::profile::Trace trace("idris-mlir-opt");
  // Every manager this tool runs carries the profile's zones, ahead of the
  // pipeline the command line gives, as idris-mlir's manager does; under
  // --idr-contracts, the contracts too, ahead of the zones, which so time
  // each pass without its checks.
  mlir::MlirOptMainConfig config = mlir::MlirOptMainConfig::createFromCLOptions();
  config.setPassPipelineSetupFn([parsed = config](mlir::PassManager &pm) {
    if (contracts)
      pm.addInstrumentation(std::make_unique<idr::ContractInstrumentation>());
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
  // The folders run the runtime's big operations, whose GMP allocates where
  // a program's does, set while no other thread exists.
  idris_rt_gmp_init();
  Invocation invocation{argc, argv};
  if (idris_rt_run_on_stack(optMain, &invocation, idr::support::toolStack,
                            idr::support::toolStackGuard, exhausted) != 0) {
    static constexpr char message[] = "idris-mlir-opt: no stack could be reserved\n";
    (void)!write(2, message, sizeof message - 1);
    return 1;
  }
  return invocation.status;
}
