// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir-opt: mlir-opt with the idr dialect, passes and pipeline
// registered. Like idris-mlir, it runs on the runtime's reserved-stack
// runner, on the tools' stack, so the nested constants MLIR's parser and
// printer recurse over are bounded by memory, not by the process's stack.
// PIN(mlir-recursion)

#include "idr/InitIdr.h"
#include "idr/Support/Profile.h"
#include "idr/Support/Stack.h"
#include "idr/Transforms/Contracts.h"
#include "idr/Transforms/Expect.h"
#include "idr/Transforms/Pipeline.h"

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

#include <memory>
#include <string>

namespace {

// A test's check of every pass as it runs, never a choice of how a program is compiled.
llvm::cl::opt<bool> contracts(
    "idr-contracts",
    llvm::cl::desc("Check after every pass on the module or the program the relations it must "
                   "keep, and fail naming the pass that broke one"),
    llvm::cl::init(false));

int optMain(int argc, char **argv) {
  llvm::InitLLVM init(argc, argv);
  mlir::registerAllPasses();
  idr::registerIdrPasses();
  idr::registerIdrPipeline();
  idr::registerContractTestPass();
  idr::registerFactsTestPass();
  // Upstream's dialects and extensions, as mlir-opt has them, then idr's,
  // whose schedule library is written in upstream's transform ops.
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  idr::registerIdrDialects(registry);
  auto [inputPath, outputPath] =
      mlir::registerAndParseCLIOptions(argc, argv, "idris-mlir-opt: the idr dialect\n", registry);
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
  if (config.shouldShowDialects() || config.shouldListPasses())
    return mlir::failed(mlir::MlirOptMain(llvm::outs(), nullptr, registry, config));
  std::string error;
  std::unique_ptr<llvm::MemoryBuffer> input = mlir::openInputFile(inputPath, &error);
  if (!input) {
    llvm::errs() << error << "\n";
    return 1;
  }
  std::unique_ptr<llvm::ToolOutputFile> output = mlir::openOutputFile(outputPath, &error);
  if (!output) {
    llvm::errs() << error << "\n";
    return 1;
  }
  if (mlir::failed(mlir::MlirOptMain(output->os(), std::move(input), registry, config)))
    return 1;
  output->keep();
  return 0;
}

} // namespace

int main(int argc, char **argv) {
  return idr::support::runTool("idris-mlir-opt", [&] { return optMain(argc, argv); });
}
