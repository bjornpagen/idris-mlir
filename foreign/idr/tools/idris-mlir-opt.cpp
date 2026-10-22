// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir-opt: mlir-opt with the idr dialect, passes and pipeline
// registered (--idr-pipeline, or a slice of it between two stages). Like
// idris-mlir, it runs on the runtime's runner, on the tools' small stack
// (idr/Driver/Tool.h). A test's checks run in it as in idris-mlir: the
// contracts (--idr-contracts) and the properties of the stages
// (--idr-expect-at), each with its last word on the module the pipeline
// left; --idr-action-tags names every action the passes take, which a
// debug counter skips. A module the frontend refused is refused before its
// first pass, as idris-mlir refuses it, and --report writes idris-mlir's
// report of the run (idr/Driver/Fold.h, the one both write).

#include "idr/Driver/Fold.h"
#include "idr/Driver/Tool.h"
#include "idr/Driver/Verdict.h"
#include "idr/IR/IdrDialect.h"
#include "idr/InitIdr.h"
#include "idr/Support/Profile.h"
#include "idr/Transforms/Contracts.h"
#include "idr/Transforms/Expect.h"
#include "idr/Transforms/Pipeline.h"

#include "idr/IR/Generated/Actions.h.inc"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/FileUtilities.h"
#include "mlir/Support/TypeID.h"
#include "mlir/Tools/mlir-opt/MlirOptMain.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/ThreadPool.h"
#include "llvm/Support/Threading.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/raw_ostream.h"

#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>

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

// idris-mlir's report of the run, an output: the verdict, each diagnostic
// with the rule it refuses the program by, and each pass's statistics and
// footprint, written whatever the verdict.
llvm::cl::opt<std::string> reportPath(
    "report",
    llvm::cl::desc("Write the run's verdict, diagnostics and pass statistics to this file, "
                   "whatever the verdict, as idris-mlir does"),
    llvm::cl::init(""));

// The refusals the frontend left in a module in place of a program,
// re-emitted (reemitRefusals, idris-mlir's own) as a precondition of the
// first pass of the pipeline: a module that holds one is refused, and
// MLIR's pass manager runs neither that pass nor any after it, as
// idris-mlir runs none on it. A module read and printed with no pass is
// not compiled, so nothing refuses it. The first pass the manager
// instruments is the pipeline's first, on the module this tool read, so the
// refusals are read there, once: no pass adds one.
class Refusals final : public mlir::PassInstrumentation {
public:
  void runBeforePass(mlir::Pass *pass, mlir::Operation *op) override {
    std::call_once(read, [&] {
      // A refusal's parent is a module, which MlirOptMain reads the input as
      // unless told it is another op (--no-implicit-module): such an op holds
      // no refusal at its top.
      if (auto module = mlir::dyn_cast<mlir::ModuleOp>(op))
        if (mlir::failed(idr::driver::reemitRefusals(module)))
          signalPassFailure(pass);
    });
  }

private:
  std::once_flag read;
};

// The report's fold of each diagnostic (foldDiagnostics, idris-mlir's own)
// on each context MlirOptMain makes for the input, from the moment the
// context loads the idr dialect: MlirOptMain hands a tool a context only
// with its pass manager, after the parse and the verifier have spoken.
// The dialect's loading is soon enough, since a refusal's rule is the
// dialect's attribute, so no refusal is made before it; and late enough,
// since MlirOptMain registers its printers on a context before the input's
// parse loads the dialect, so the fold, the newest handler, sees each
// diagnostic before a printer takes it, as idris-mlir's does.
class FoldInto final : public mlir::DialectExtension<FoldInto, idr::IdrDialect> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(FoldInto)

  explicit FoldInto(idr::driver::Outcome &outcome) : outcome(&outcome) {}

  void apply(mlir::MLIRContext *context, idr::IdrDialect *) const override {
    idr::driver::foldDiagnostics(*context, *outcome);
  }

private:
  idr::driver::Outcome *outcome;
};

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
  // The run's outcome, which the report is written from, when one is asked
  // for; declared before MlirOptMain makes the contexts whose diagnostics
  // fold into it, so it outlives them.
  std::optional<idr::driver::Outcome> outcome;
  if (!reportPath.empty()) {
    outcome.emplace();
    registry.addExtension(mlir::TypeID::get<FoldInto>(), std::make_unique<FoldInto>(*outcome));
  }
  // Every manager this tool runs refuses, before its first pass, a module
  // the frontend refused, and carries the profile's zones and, under
  // --report, the report's sums, ahead of the pipeline the command line
  // gives, as idris-mlir's manager does; a test's checks come ahead of the
  // zones, which so time each pass without them, and have their last word
  // after the pipeline.
  mlir::MlirOptMainConfig config = mlir::MlirOptMainConfig::createFromCLOptions();
  config.setPassPipelineSetupFn([parsed = config, &stages, &outcome](mlir::PassManager &pm) {
    pm.addInstrumentation(std::make_unique<Refusals>());
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
    if (outcome)
      idr::driver::foldPasses(pm, *outcome);
    if (mlir::failed(parsed.setupPassPipeline(pm)))
      return mlir::failure();
    if (checking != nullptr || staging != nullptr)
      pm.addPass(std::make_unique<Finish>(checking, staging));
    return mlir::success();
  });
  // The pool every context MlirOptMain makes shares, every CPU, each worker
  // on the tools' stack as this thread is; declared before MlirOptMain runs,
  // so it outlives it. --mlir-disable-threading still disables threading.
  llvm::StdThreadPool pool(idr::driver::onToolStack(llvm::hardware_concurrency()));
  config.setThreadPool(&pool);
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
  mlir::LogicalResult ran = mlir::MlirOptMain(output->os(), std::move(input), registry, config);
  if (outcome) {
    // A run that failed with no error folded said why before the idr
    // dialect was loaded, or not at all: either way the failure is the
    // compiler's, as idris-mlir holds a pipeline that fails with no error.
    if (mlir::failed(ran) && outcome->verdict() == idr::driver::Verdict::Accepted)
      outcome->see(idr::driver::Verdict::Internal);
    // Whatever the verdict: the report says why the run failed. One that
    // cannot be written fails the run, which then keeps no output.
    if (std::error_code written = idr::driver::writeReport(reportPath, *outcome)) {
      idr::driver::Report() << "cannot write " << reportPath.getValue() << ": "
                            << written.message();
      return 1;
    }
  }
  if (mlir::failed(ran))
    return 1;
  output->keep();
  return 0;
}

} // namespace

int main(int argc, char **argv) {
  return idr::driver::runTool([&] { return optMain(argc, argv); });
}
