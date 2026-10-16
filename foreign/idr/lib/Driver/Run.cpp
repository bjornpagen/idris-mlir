// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The in-process part of a compilation, from a module to the objects of
// its bins: a handoff module through the idr pipeline in one pass manager
// and then LLVM, the pipeline's output through LLVM alone; and what each
// step reported, folded into the compilation's outcome.

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Compile.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Report.h"
#include "idr/Driver/Runtime.h"
#include "idr/Driver/Verdict.h"
#include "idr/Support/Profile.h"
#include "idr/Target/Target.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Debug/BreakpointManagers/TagBreakpointManager.h"
#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/DLTI/DLTI.h"
#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/Visitors.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/LLVM.h"
#include "mlir/Support/Timing.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Export.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/ThreadPool.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Triple.h"
#include "llvm/Transforms/IPO/Internalize.h"

#include <cstdint>
#include <memory>
#include <string>

using namespace idr::driver;

namespace {

// The status of a compilation a step stopped.
int stopped(Outcome &outcome) {
  outcome.failed();
  return statusOf(outcome.verdict());
}

// What a module is, by what it holds, never by an option: the frontend's,
// a handoff module, which holds an idr.program and goes through the
// pipeline and then LLVM; or the pipeline's output, the LLVM dialect
// alone, which goes to LLVM as it is.
enum class ModuleKind : std::uint8_t { Handoff, Lowered };

// The module's kind: an idr.program among its ops makes it a handoff
// module, whose every op must be of a dialect the frontend writes;
// otherwise every op must be the LLVM dialect's. An error at the first op
// that is not, naming it (idris-mlir prints no op on a diagnostic), and
// failure: a module half lowered (an arith op in an llvm.func) is neither,
// and LLVM's translation would fail on it with no word of why. An op of a
// dialect neither kind is written in (func) does not parse.
mlir::FailureOr<ModuleKind> kindOf(mlir::ModuleOp module, const mlir::DialectRegistry &handoff) {
  auto written = [&](mlir::Operation *op) {
    return static_cast<bool>(handoff.getDialectAllocator(op->getName().getDialectNamespace()));
  };
  auto lowered = [](mlir::Operation *op) {
    return mlir::isa<mlir::LLVM::LLVMDialect>(op->getDialect());
  };
  // A kind, the ops a module of it holds, and what an op it may not hold is
  // said to be.
  struct Holds {
    ModuleKind kind;
    llvm::function_ref<bool(mlir::Operation *)> op;
    llvm::StringLiteral otherwise;
  };
  const Holds holds =
      module.getOps<idr::ProgramOp>().empty()
          ? Holds{ModuleKind::Lowered, lowered,
                  "is no op of the LLVM dialect, in a module that holds no idr.program: such "
                  "a module is the pipeline's output"}
          : Holds{ModuleKind::Handoff, written,
                  "is of no dialect the frontend writes, in a module that holds an idr.program"};
  mlir::WalkResult walked =
      module.getBody()->walk<mlir::WalkOrder::PreOrder>([&](mlir::Operation *op) {
        if (holds.op(op))
          return mlir::WalkResult::advance();
        op->emitOpError(holds.otherwise);
        return mlir::WalkResult::interrupt();
      });
  if (walked.wasInterrupted())
    return mlir::failure();
  return holds.kind;
}

// The pipeline, idr-target first, in one manager, so that what a pass
// preserves the next one finds. --stats, LLVM's own option, prints its
// statistics too; MLIR's own pass-manager options (IR printing, the module
// after each pass with -mlir-print-ir-tree-dir, crash reproducers,
// -mlir-pass-statistics) apply to it. The report's instrumentation reads
// each pass's statistics around each of its runs, before MLIR merges the
// copies' statistics to print them. The timer is added last: the
// instrumentations unwind in reverse, so it stops before IR is printed,
// and a pass's row is the pass's own time. The manager goes, and prints
// its statistics, before LLVM starts. Zero, or an exit status.
int runPipeline(mlir::ModuleOp module, Outcome &outcome, mlir::TimingScope &rootTiming) {
  mlir::PassManager pm(module.getContext());
  if (llvm::AreStatisticsEnabled())
    pm.enableStatistics(mlir::PassDisplayMode::List);
  if (mlir::failed(mlir::applyPassManagerCLOptions(pm)))
    return usage;
  idr::profile::addInstrumentation(pm);
  pm.addInstrumentation(foldStatistics(outcome));
  pm.enableTiming(rootTiming);
  // The module's target, which every pass reads: idr-entry tells the
  // runtime's entry which of its features to test; the object code is
  // compiled for it.
  pm.addPass(idr::createIdrTarget());
  idr::buildPipeline(pm);
  bool ran = mlir::succeeded(pm.run(module));
  // Any error stops the compilation, whether or not what reported it
  // failed: an error from a pass that then goes on is an error all the
  // same.
  if (!ran || outcome.verdict() != Verdict::Accepted) {
    int status = stopped(outcome);
    if (outcome.verdict() == Verdict::Internal)
      Report() << "internal error: the pipeline " << (ran ? "reported an error" : "failed");
    return status;
  }
  return ok;
}

// LLVM IR, joined with the runtime into one module; every symbol but main
// internalized; LLVM's O3 pipeline once, on the whole program; then the
// optimized module cut into bins, each compiled to object code for the CPU
// on `pool`. Each stage has a timer of its own, so -mlir-timing says which
// one a compilation spends its time on.
int toObjects(mlir::ModuleOp module, Artifacts &artifacts, const llvm::Target &target,
              const llvm::Triple &triple, llvm::ThreadPoolInterface &pool, Outcome &outcome,
              mlir::TimingScope &rootTiming) {
  mlir::TimingScope llvmTiming = rootTiming.nest("LLVM");
  auto moduleTarget =
      module->getAttrOfType<mlir::LLVM::TargetAttr>(mlir::LLVM::LLVMDialect::getTargetAttrName());
  if (!moduleTarget) {
    Report() << "internal error: the module lost its #llvm.target";
    return failure;
  }
  // The runtime it is linked with and every link are for the build's
  // triple; a module the pipeline lowered for another cannot join them.
  if (llvm::StringRef compiledFor = moduleTarget.getTriple().getValue();
      compiledFor != targetTriple) {
    Report() << "internal error: the module is compiled for " << compiledFor
             << ", and idris-mlir for " << targetTriple;
    return failure;
  }
  std::string features =
      moduleTarget.getFeatures() ? moduleTarget.getFeatures().getFeaturesString() : "";
  llvm::StringRef cpu = moduleTarget.getChip().getValue();
  llvm::Expected<std::unique_ptr<llvm::TargetMachine>> made =
      idr::target::machine(target, triple, cpu, features);
  if (!made) {
    Report() << "internal error: " << llvm::toString(made.takeError());
    return failure;
  }
  llvm::TargetMachine &machine = **made;
  llvm::LLVMContext llvmContext;
  std::unique_ptr<llvm::Module> llvmModule;
  {
    IDR_ZONE_IN("translate", LLVM);
    mlir::TimingScope stage = llvmTiming.nest("translate");
    llvmModule = mlir::translateModuleToLLVMIR(module, llvmContext);
    if (!llvmModule || outcome.verdict() != Verdict::Accepted) {
      int status = stopped(outcome);
      if (outcome.verdict() == Verdict::Internal)
        Report() << "internal error: translation to LLVM IR failed";
      return status;
    }
    llvmModule->setTargetTriple(triple);
    llvmModule->setDataLayout(machine.createDataLayout());
    // Every target's executables are position-independent.
    llvmModule->setPICLevel(llvm::PICLevel::BigPIC);
    llvmModule->setPIELevel(llvm::PIELevel::Large);
  }
  {
    IDR_ZONE_IN("link runtime", LLVM);
    mlir::TimingScope stage = llvmTiming.nest("link runtime");
    if (!linkRuntime(*llvmModule, target, triple, machine))
      return failure;
    retarget(*llvmModule, machine);
    // The program is whole, so nothing but the process entry is visible
    // outside it; O3 then removes what main does not reach. The runtime's
    // available_externally bodies stay as they are: a declaration with a
    // body.
    llvm::internalizeModule(
        *llvmModule, [](const llvm::GlobalValue &value) { return value.getName() == "main"; });
  }
  {
    IDR_ZONE_IN("optimize", LLVM);
    mlir::TimingScope stage = llvmTiming.nest("optimize");
    idr::target::optimize(*llvmModule, machine);
  }
  // After O3 code generation is local to each function, so the bins are
  // compiled at once; how many there are follows from the module's size,
  // never from the pool's.
  IDR_ZONE_IN("codegen", LLVM);
  mlir::TimingScope stage = llvmTiming.nest("codegen");
  return writeObjects(*llvmModule, target, triple, cpu, features, pool, artifacts) ? ok : failure;
}

} // namespace

const llvm::Target *idr::driver::nativeTarget(const llvm::Triple &triple) {
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  // The runtime linked into the program carries inline assembly.
  llvm::InitializeNativeTargetAsmParser();
  std::string error;
  const llvm::Target *target = llvm::TargetRegistry::lookupTarget(triple, error);
  if (!target)
    Report() << error;
  return target;
}

int idr::driver::run(Artifacts &artifacts, mlir::TimingScope &rootTiming, Outcome &outcome) {
  // A module is one of two kinds, by what it holds (kindOf): a handoff
  // module, as the frontend writes one, holds one idr.program, which the
  // pipeline's program passes run nested on, and goes through the pipeline
  // and then LLVM; a module of the LLVM dialect alone, the pipeline's
  // output, goes to LLVM as it is. It is parsed with the dialects the
  // frontend writes and the two the pipeline's output is written in, LLVM
  // and DLTI, so an op of any other fails to parse; its kind then says
  // which of them its ops may be of. The rest load after. The context runs
  // the function groups over the functions in parallel unless
  // --mlir-disable-threading; two compiles of one module are the same bytes
  // either way, since no pass keeps state a worker thread shares.
  mlir::DialectRegistry handoff;
  handoff.insert<idr::IdrDialect, mlir::arith::ArithDialect, mlir::math::MathDialect,
                 mlir::ub::UBDialect, mlir::memref::MemRefDialect, mlir::tensor::TensorDialect,
                 mlir::scf::SCFDialect>();
  // How a closure moves through the upstream ops that can hold one, which
  // the verifier checks from the parse on.
  idr::registerFlowInterfaceExternalModels(handoff);
  mlir::DialectRegistry readable;
  handoff.appendTo(readable);
  readable.insert<mlir::LLVM::LLVMDialect, mlir::DLTIDialect>();
  // The one pool of the compilation, which the function passes and the
  // bins' code generation run on, sized by --num-threads (every CPU by
  // default); declared before the context so it outlives it, as
  // upstream's tools declare theirs. --mlir-disable-threading still wins
  // for the passes, the context then ignoring it.
  llvm::ThreadPoolStrategy strategy;
  strategy.ThreadsRequested = threadBudget();
  llvm::StdThreadPool pool(strategy);
  // Created disabled so the pool can be set (setThreadPool requires
  // it and enables threading itself); --mlir-disable-threading keeps
  // it disabled, as upstream's tools arrange the same pair.
  mlir::MLIRContext context(readable, mlir::MLIRContext::Threading::DISABLED);
  context.setThreadPool(pool);
  llvm::Triple triple(targetTriple);
  const llvm::Target *target = nativeTarget(triple);
  if (!target)
    return failure;

  llvm::SourceMgr sources;
  mlir::SourceMgrDiagnosticHandler diagnostics(sources, &context);
  // Every diagnostic into the outcome, and then on to this handler, which
  // prints it. A refusal carries the rule it names as data, and is printed
  // at the location of the user's code the module carries (MLIR's handler
  // shows the source line).
  foldDiagnostics(context, outcome);
  // -mlir-timing, MLIR's own option, times the parse (with the verification
  // that follows it), each pass and LLVM's stages, under the compilation's
  // root.
  mlir::OwningOpRef<mlir::ModuleOp> module;
  {
    IDR_ZONE_IN("parse", Parse);
    mlir::TimingScope parseTiming = rootTiming.nest("parse");
    module = mlir::parseSourceFile<mlir::ModuleOp>(artifacts.modulePath(), sources, &context);
  }
  // The parsed module is verified, and some of the verifier's rules are the
  // user's (a type that can reach itself through an array).
  if (!module || outcome.verdict() != Verdict::Accepted)
    return stopped(outcome);
  mlir::FailureOr<ModuleKind> kind = kindOf(*module, handoff);
  if (mlir::failed(kind))
    return stopped(outcome);
  mlir::DialectRegistry everything;
  mlir::registerAllDialects(everything);
  mlir::registerAllExtensions(everything);
  mlir::registerBuiltinDialectTranslation(everything);
  mlir::registerLLVMDialectTranslation(everything);
  // The schedules the pipeline's interpreter runs, loaded with the
  // transform dialect.
  idr::target::registerScheduleLibrary(everything);
  context.appendDialectRegistry(everything);

  // MLIR's action handler: -log-actions-to and -profile-actions-to, which
  // --log-actions-tags narrows. With no tag given every action is logged,
  // which an empty filter would not do.
  mlir::tracing::DebugConfig debugConfig = mlir::tracing::DebugConfig::createFromCLOptions();
  mlir::tracing::TagBreakpointManager loggedTags;
  for (const std::string &tag : logActionsTags)
    loggedTags.addBreakpoint(tag);
  if (!logActionsTags.empty())
    debugConfig.addLogActionLocFilter(&loggedTags);
  mlir::tracing::InstallDebugHandler debugHandler(context, debugConfig);
  // MLIR reports what it cannot set up as asked (a file --log-actions-to
  // cannot open) as an error and goes on without it.
  if (outcome.verdict() != Verdict::Accepted)
    return usage;

  if (*kind == ModuleKind::Handoff)
    if (int code = runPipeline(*module, outcome, rootTiming))
      return code;
  return toObjects(*module, artifacts, *target, triple, pool, outcome, rootTiming);
}
