// The in-process part of a compilation: the idr pipeline in one pass
// manager, then LLVM, from a module to an object.

#include "idr/IR/IdrDialect.h"
#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Compile.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Report.h"
#include "idr/Driver/Runtime.h"
#include "idr/Support/Profile.h"
#include "idr/Target/Target.h"
#include "idr/Transforms/Pipeline.h"
#include "idr/Transforms/Simplify.h"

#include "mlir/Debug/BreakpointManagers/TagBreakpointManager.h"
#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/DialectRegistry.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassManager.h"
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
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Triple.h"
#include "llvm/Transforms/IPO/Internalize.h"

#include <memory>
#include <string>
#include <system_error>
#include <vector>

using namespace idr::driver;

namespace {

// Which errors were reported. Any error fails the compilation, whether or
// not what reported it failed: an error from a pass that then goes on is an
// error all the same. A rejection (`unsupported (<reason>): ...`) is the
// user's, printed at the location of the user's code the module carries
// (MLIR's diagnostic handler, which shows the source line); any other
// error is internal.
struct Verdict {
  bool errors = false;
  bool rejected = false;
};

int status(const Verdict &verdict) { return verdict.rejected ? rejected : failure; }

// --without: a pass of the pipeline other than idr-lower, or an option of
// idr-rc or idr-demand turned off, so that a misspelling measures nothing
// by accident. Whether every name was one.
bool leaveOut(idr::PipelineOptions &options) {
  std::vector<std::string> passes = idr::pipelinePassNames();
  for (const std::string &name : without) {
    bool option = name == "reuse" || name == "sink" || name == "in-place";
    bool pass = name != "idr-lower" && llvm::StringRef(name).starts_with("idr-") &&
                llvm::is_contained(passes, name);
    if (!option && !pass) {
      Report() << "--without names " << name
               << ", which is neither a pass of the pipeline nor reuse, sink or in-place";
      return false;
    }
    options.without.insert(name);
  }
  // --demand-in-place asks idr-demand to reject a program that breaks the
  // promise; leaving the checker, or its one check, out would keep the
  // promise by not looking, which is never what was asked.
  if (options.demandInPlace &&
      (options.without.contains("idr-demand") || options.without.contains("in-place"))) {
    Report() << "--demand-in-place with --without "
             << (options.without.contains("idr-demand") ? "idr-demand" : "in-place")
             << ": the promise is asked of the checker that is left out";
    return false;
  }
  return true;
}

// The pipeline, idr-target first, in one manager, so that what a pass
// preserves the next one finds. --stats, LLVM's own option, prints its
// statistics too; MLIR's own pass-manager options (IR printing, crash
// reproducers, -mlir-pass-statistics) apply to it. The timer is added last:
// the instrumentations unwind in reverse, so it stops before a dump is
// printed, and a pass's row is the pass's own time. The manager goes, and
// prints its statistics, before LLVM starts. Zero, or an exit status.
int runPipeline(mlir::ModuleOp module, const idr::PipelineOptions &options,
                const Verdict &verdict, mlir::TimingScope &rootTiming) {
  mlir::PassManager pm(module.getContext());
  if (llvm::AreStatisticsEnabled())
    pm.enableStatistics(mlir::PassDisplayMode::List);
  if (mlir::failed(mlir::applyPassManagerCLOptions(pm)))
    return usage;
  pm.addInstrumentation(idr::createSimplifyInstrumentation());
  DumpAfterEachPass *dumps = nullptr;
  if (!dumpDir.empty()) {
    auto owned = std::make_unique<DumpAfterEachPass>(dumpDir);
    dumps = owned.get();
    pm.addInstrumentation(std::move(owned));
  }
  idr::profile::addInstrumentation(pm);
  pm.enableTiming(rootTiming);
  // The module's target, which every pass reads: idr-lower tells the
  // runtime's entry which of its features to test; the object code is
  // compiled for it.
  pm.addPass(idr::createIdrTarget());
  idr::buildPipeline(pm, options);
  bool ran = mlir::succeeded(pm.run(module));
  if (!ran || verdict.errors) {
    if (!verdict.rejected)
      Report() << "internal error: the pipeline " << (ran ? "reported an error" : "failed");
    return status(verdict);
  }
  return dumps && dumps->failed() ? failure : ok;
}

// LLVM IR, joined with the runtime into one module; every symbol but main
// internalized; LLVM's O3 pipeline; object code for the CPU. Each stage has
// a timer of its own, so -mlir-timing says which one a compilation spends
// its time on.
int toObject(mlir::ModuleOp module, llvm::StringRef objectPath, const llvm::Target &target,
             const llvm::Triple &triple, const Verdict &verdict, mlir::TimingScope &rootTiming) {
  mlir::TimingScope llvmTiming = rootTiming.nest("LLVM");
  auto moduleTarget =
      module->getAttrOfType<mlir::LLVM::TargetAttr>(mlir::LLVM::LLVMDialect::getTargetAttrName());
  if (!moduleTarget) {
    Report() << "internal error: the module lost its #llvm.target";
    return failure;
  }
  std::string features =
      moduleTarget.getFeatures() ? moduleTarget.getFeatures().getFeaturesString() : "";
  std::unique_ptr<llvm::TargetMachine> machine =
      idr::target::machine(target, triple, moduleTarget.getChip().getValue(), features);
  if (!machine) {
    Report() << "internal error: no target machine for " << targetTriple;
    return failure;
  }
  llvm::LLVMContext llvmContext;
  std::unique_ptr<llvm::Module> llvmModule;
  {
    IDR_ZONE_IN("translate", LLVM);
    mlir::TimingScope stage = llvmTiming.nest("translate");
    llvmModule = mlir::translateModuleToLLVMIR(module, llvmContext);
    if (!llvmModule || verdict.errors) {
      if (!verdict.rejected)
        Report() << "internal error: translation to LLVM IR failed";
      return status(verdict);
    }
    llvmModule->setTargetTriple(triple);
    llvmModule->setDataLayout(machine->createDataLayout());
    // Every target's executables are position-independent.
    llvmModule->setPICLevel(llvm::PICLevel::BigPIC);
    llvmModule->setPIELevel(llvm::PIELevel::Large);
  }
  {
    IDR_ZONE_IN("link runtime", LLVM);
    mlir::TimingScope stage = llvmTiming.nest("link runtime");
    if (!linkRuntime(*llvmModule, target, triple, *machine))
      return failure;
    retarget(*llvmModule, *machine);
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
    idr::target::optimize(*llvmModule, *machine);
  }
  IDR_ZONE_IN("codegen", LLVM);
  mlir::TimingScope stage = llvmTiming.nest("codegen");
  return emit(*llvmModule, *machine, objectPath) ? ok : failure;
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

int idr::driver::run(llvm::StringRef modulePath, llvm::StringRef objectPath,
                     mlir::TimingScope &rootTiming) {
  // The module is parsed with exactly the dialects the frontend writes, so
  // an op of any other fails to parse. The rest load after. The context
  // runs the function groups over the functions in parallel unless
  // --mlir-disable-threading; two compiles of one module are the same bytes
  // either way, since no pass keeps state a worker thread shares.
  mlir::DialectRegistry handoff;
  handoff.insert<idr::IdrDialect, mlir::arith::ArithDialect, mlir::math::MathDialect,
                 mlir::ub::UBDialect, mlir::memref::MemRefDialect>();
  mlir::MLIRContext context(handoff);
  llvm::Triple triple(targetTriple);
  const llvm::Target *target = nativeTarget(triple);
  if (!target)
    return failure;

  llvm::SourceMgr sources;
  mlir::SourceMgrDiagnosticHandler diagnostics(sources, &context);
  Verdict verdict;
  context.getDiagEngine().registerHandler([&](mlir::Diagnostic &diagnostic) {
    if (diagnostic.getSeverity() == mlir::DiagnosticSeverity::Error) {
      verdict.errors = true;
      std::string message = diagnostic.str();
      if (llvm::StringRef(message).starts_with("unsupported ("))
        verdict.rejected = true;
    }
    return mlir::failure();
  });
  // -mlir-timing, MLIR's own option, times the parse (with the verification
  // that follows it), each pass and LLVM's stages, under the compilation's
  // root.
  mlir::OwningOpRef<mlir::ModuleOp> module;
  {
    IDR_ZONE_IN("parse", Parse);
    mlir::TimingScope parseTiming = rootTiming.nest("parse");
    module = mlir::parseSourceFile<mlir::ModuleOp>(modulePath, sources, &context);
  }
  // The parsed module is verified, and some of the verifier's rules are the
  // user's (a type that can reach itself through an array).
  if (!module || verdict.errors)
    return status(verdict);
  mlir::DialectRegistry everything;
  mlir::registerAllDialects(everything);
  mlir::registerAllExtensions(everything);
  mlir::registerBuiltinDialectTranslation(everything);
  mlir::registerLLVMDialectTranslation(everything);
  context.appendDialectRegistry(everything);

  // MLIR's action handler: the debug counters (-mlir-debug-counter), or
  // -log-actions-to and -profile-actions-to, which --log-actions-tags
  // narrows. With no tag given every action is logged, which an empty
  // filter would not do.
  mlir::tracing::DebugConfig debugConfig = mlir::tracing::DebugConfig::createFromCLOptions();
  mlir::tracing::TagBreakpointManager loggedTags;
  for (const std::string &tag : logActionsTags)
    loggedTags.addBreakpoint(tag);
  if (!logActionsTags.empty())
    debugConfig.addLogActionLocFilter(&loggedTags);
  mlir::tracing::InstallDebugHandler debugHandler(context, debugConfig);
  // MLIR reports what it cannot set up as asked (a file --log-actions-to
  // cannot open, debug counters with action logging) as an error and goes
  // on without it.
  if (verdict.errors)
    return usage;

  idr::PipelineOptions options;
  options.demandInPlace = demandInPlace;
  if (!leaveOut(options))
    return usage;
  // --dump-dir: the directory the dumps go into, made here.
  if (!dumpDir.empty())
    if (std::error_code made = llvm::sys::fs::create_directories(dumpDir)) {
      cannotWrite(dumpDir, made);
      return failure;
    }

  if (int code = runPipeline(*module, options, verdict, rootTiming))
    return code;
  return toObject(*module, objectPath, *target, triple, verdict, rootTiming);
}
