// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir-opt: mlir-opt with the idr dialect, passes and pipeline
// registered (--idr-pipeline, or a slice of it between two stages). Like
// idris-mlir, it runs on the runtime's runner, on the tools' small stack
// (idr/Driver/Tool.h). A test's checks run in it as in idris-mlir: the
// contracts (--idr-contracts) and the properties of the stages
// (--idr-expect-at), each with its last word on the module the pipeline
// left; --idr-action-tags names every action the passes take, which a
// debug counter skips.

#include "idr/Driver/Tool.h"
#include "idr/InitIdr.h"
#include "idr/Support/Profile.h"
#include "idr/Transforms/Contracts.h"
#include "idr/Transforms/Expect.h"
#include "idr/Transforms/Pipeline.h"

#include "idr/IR/Generated/Actions.h.inc"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/FileUtilities.h"
#include "mlir/Support/TypeID.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/raw_ostream.h"

#include <memory>
#include <string>
#include <string_view>

namespace {

// A test's check of every pass as it runs, never a choice of how a program is compiled.
llvm::cl::opt<bool> contracts(
    "idr-contracts",
    llvm::cl::desc("Check after every pass on the module or the program the relations it must "
                   "keep, and fail naming the pass that broke one"),
    llvm::cl::init(false));

// A test's statement of what holds at a stage of the pipeline
// (idr/Transforms/Expect.h), as idris-mlir has it.
llvm::cl::list<std::string> expectAt(
    "idr-expect-at",
    llvm::cl::desc("Check properties of a stage after every pass that leaves the program at "
                   "it: <stage>:<property>,..."));

// The tags of every action the passes take, one per line, from the
// specification's list, so a test draws the actions it skips from them.
llvm::cl::opt<bool> actionTags(
    "idr-action-tags",
    llvm::cl::desc("Print the tag of every action the passes take, one per line, and exit"),
    llvm::cl::init(false));

// The checks with a last word on the module the pipeline left, which the
// pass manager instruments no end of: asked by the last pass of the
// pipeline the command line gives, which nothing else runs.
class Finish final : public mlir::PassWrapper<Finish, mlir::OperationPass<mlir::ModuleOp>> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Finish)

  Finish(idr::ContractInstrumentation *contracts, idr::expect::StageInstrumentation *stages)
      : contracts(contracts), stages(stages) {}

  llvm::StringRef getArgument() const override { return "idr-finish-checks"; }

  void runOnOperation() override {
    mlir::ModuleOp module = getOperation();
    if (contracts != nullptr && mlir::failed(contracts->finish(module)))
      return signalPassFailure();
    if (stages != nullptr && mlir::failed(stages->finish(module)))
      return signalPassFailure();
  }

private:
  idr::ContractInstrumentation *contracts;
  idr::expect::StageInstrumentation *stages;
};

int optMain(int argc, char **argv) {
  llvm::InitLLVM init(argc, argv);
  mlir::registerAllPasses();
  idr::registerIdrPasses();
  idr::registerIdrPipeline();
  idr::registerContractTestPass();
  // Upstream's dialects and extensions, as mlir-opt has them, then idr's,
  // whose schedule library is written in upstream's transform ops.
  mlir::DialectRegistry registry;
  mlir::registerAllDialects(registry);
  mlir::registerAllExtensions(registry);
  idr::registerIdrDialects(registry);
  auto [inputPath, outputPath] =
      mlir::registerAndParseCLIOptions(argc, argv, "the idr dialect\n", registry);
  if (actionTags) {
    for (std::string_view tag : idr::actions::tags)
      llvm::outs() << tag << "\n";
    return 0;
  }
  // The stage requests, read once, before any input: a stage or a property
  // that is none is a usage error, said on a scratch context.
  llvm::SmallVector<idr::expect::StageRequest> stages;
  {
    mlir::MLIRContext scratch;
    for (const std::string &written : expectAt) {
      mlir::FailureOr<llvm::SmallVector<idr::expect::StageRequest>> read =
          idr::expect::parseStageRequests(&scratch, written);
      if (mlir::failed(read))
        return 2;
      llvm::append_range(stages, *read);
    }
  }
  // --time-trace, when it named a file: written as this returns.
  idr::profile::Trace trace(idr::driver::toolName);
  // Every manager this tool runs carries the profile's zones, ahead of the
  // pipeline the command line gives, as idris-mlir's manager does; a test's
  // checks ahead of the zones, which so time each pass without them, and
  // their last word after the pipeline.
  mlir::MlirOptMainConfig config = mlir::MlirOptMainConfig::createFromCLOptions();
  config.setPassPipelineSetupFn([parsed = config, &stages](mlir::PassManager &pm) {
    idr::ContractInstrumentation *checking = nullptr;
    idr::expect::StageInstrumentation *staging = nullptr;
    if (contracts) {
      auto owned = std::make_unique<idr::ContractInstrumentation>();
      checking = owned.get();
      pm.addInstrumentation(std::move(owned));
    }
    if (!stages.empty()) {
      auto owned = std::make_unique<idr::expect::StageInstrumentation>(stages);
      staging = owned.get();
      pm.addInstrumentation(std::move(owned));
    }
    idr::profile::addInstrumentation(pm);
    if (mlir::failed(parsed.setupPassPipeline(pm)))
      return mlir::failure();
    if (checking != nullptr || staging != nullptr)
      pm.addPass(std::make_unique<Finish>(checking, staging));
    return mlir::success();
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
  return idr::driver::runTool([&] { return optMain(argc, argv); });
}
