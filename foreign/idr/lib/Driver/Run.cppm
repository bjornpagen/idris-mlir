// idr.driver:run: one compilation, the idr pipeline, step by step, then LLVM,
// into the output; or --prepare-runtime.
export module idr.driver:run;

import idr.mlir;
import idr.dialect;
import idr.target;

import :cpu;
import :dump;
import :emit;
import :linkruntime;
import :options;
import :prepare;
import :report;
import :retarget;
import :settarget;
import :writeoutput;

namespace idr::driver {

namespace {

std::string stepName(llvm::StringRef step) {
  std::string name = step.split(',').first.str();
  return name;
}

// Which errors were reported. Any error fails the compilation, whether or
// not what reported it failed: an error from a step that then goes on is an
// error all the same. A rejection (`unsupported (<reason>): ...`) is the
// user's, at the location of the user's code the frontend reports; any
// other error is internal.
struct Verdict {
  bool errors = false;
  bool rejected = false;
};

int status(const Verdict &verdict) { return verdict.rejected ? rejected : failure; }

} // namespace

} // namespace idr::driver

export namespace idr::driver {

// The compilation: the pipeline, LLVM and the output, or --prepare-runtime;
// an exit status.
int run() {
  mlir::registerAllPasses();
  idr::registerIdrPipeline();
  // The program is parsed with exactly the contract's
  // dialects, so an op of any other fails to parse. The rest load after.
  mlir::DialectRegistry contract;
  contract.insert<mlir::func::FuncDialect, mlir::arith::ArithDialect, mlir::math::MathDialect,
                  mlir::ub::UBDialect, mlir::memref::MemRefDialect>();
  idr::registerIdr(contract);
  mlir::MLIRContext context(contract);
  // MLIR runs single-threaded, so results do not depend on
  // scheduling, and idr-eval may fork.
  context.disableMultithreading();

  if (emitKind != "obj" && emitKind != "asm" && emitKind != "llvm" && emitKind != "mlir") {
    Report() << "--emit must be obj, asm, llvm or mlir";
    return usage;
  }
  if (checkOnly == !outputPath.empty()) {
    Report() << "give either -o or --check";
    return usage;
  }
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  // The runtime linked into the program carries inline assembly.
  llvm::InitializeNativeTargetAsmParser();
  llvm::Triple triple(targetTriple);
  std::string error;
  const llvm::Target *target = llvm::TargetRegistry::lookupTarget(triple, error);
  if (!target) {
    Report() << error;
    return failure;
  }
  std::optional<Cpu> cpu = selectCpu(*target, triple);
  if (!cpu)
    return usage;
  if (prepareRuntime)
    return prepare(*target, triple, *cpu);

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
  mlir::OwningOpRef<mlir::ModuleOp> module =
      mlir::parseSourceFile<mlir::ModuleOp>(inputPath, sources, &context);
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
  if (mlir::failed(setTarget(*module, *cpu)) || verdict.errors) {
    if (!verdict.rejected)
      Report() << "internal error: the module's target could not be set";
    return status(verdict);
  }

  // --remarks prints the remarks of its categories, of every kind;
  // --remarks-file streams them, or every remark, to a YAML file.
  if (!remarks.empty() || !remarksFile.empty()) {
    std::unique_ptr<mlir::remark::detail::MLIRRemarkStreamerBase> streamer;
    if (!remarksFile.empty()) {
      auto file = mlir::remark::detail::LLVMRemarkStreamer::createToFile(
          remarksFile, llvm::remarks::Format::YAML);
      if (mlir::failed(file)) {
        Report() << "cannot write the remarks to " << remarksFile;
        return usage;
      }
      streamer = std::move(*file);
    }
    // The engine filters only the kinds whose category is set.
    std::string regex = remarks.empty() ? std::string(".*") : remarks.getValue();
    mlir::remark::RemarkCategories categories{regex, regex, regex, regex, regex};
    if (mlir::failed(mlir::remark::enableOptimizationRemarks(
            context, std::move(streamer), std::make_unique<mlir::remark::RemarkEmittingPolicyAll>(),
            categories, /*printAsEmitRemarks=*/!remarks.empty())))
      return usage;
  }
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
  // --no-eval: the idr-eval pass, wherever a pipeline runs it, is skipped;
  // every other action goes on to the handler installed before, or runs.
  if (noEval) {
    mlir::MLIRContext::HandlerTy next = std::move(context.getActionHandler());
    if (!next)
      next = [](llvm::function_ref<void()> transform, const mlir::tracing::Action &) {
        transform();
      };
    context.registerActionHandler([next = std::move(next)](llvm::function_ref<void()> transform,
                                                           const mlir::tracing::Action &action) {
      if (action.getTag() == mlir::PassExecutionAction::tag &&
          static_cast<const mlir::PassExecutionAction &>(action).getPass().getArgument() ==
              "idr-eval")
        return;
      next(transform, action);
    });
  }
  mlir::DefaultTimingManager timings;
  mlir::applyDefaultTimingManagerCLOptions(timings);
  if (timing)
    timings.setEnabled(true);
  mlir::TimingScope rootTiming = timings.getRootScope();
  // --stats, LLVM's own option: the statistics of every pass manager too.
  bool statistics = llvm::AreStatisticsEnabled();

  // --without: the names must be steps or idr-rc mechanisms, so that a
  // misspelling measures nothing by accident.
  llvm::StringSet<> omitted;
  for (const std::string &name : without) {
    bool mechanism = name == "reuse" || name == "borrow" || name == "sink";
    bool step = name != "idr-lower" && llvm::StringRef(name).starts_with("idr-") &&
                llvm::any_of(idr::pipelineSteps(),
                             [&](llvm::StringRef s) { return stepName(s) == name; });
    if (!mechanism && !step) {
      Report() << "--without names " << name
               << ", which is neither a pipeline step nor reuse, borrow or sink";
      return usage;
    }
    omitted.insert(name);
  }
  // --demand: in-place is the one promise idr-demand checks, and a
  // misspelled one would check nothing by accident.
  for (const std::string &promise : demand)
    if (promise != "in-place") {
      Report() << "--demand names " << promise << ", which is not in-place, the one promise";
      return usage;
    }
  // Every step is one pass manager, registered the same way: statistics when
  // they are on, MLIR's own pass-manager options, and this compilation's
  // timer. The step's text is the pipeline it runs.
  auto configure = [&](mlir::PassManager &pm) {
    if (statistics)
      pm.enableStatistics(mlir::PassDisplayMode::List);
    if (mlir::failed(mlir::applyPassManagerCLOptions(pm)))
      return false;
    pm.enableTiming(rootTiming);
    return true;
  };
  unsigned index = 0;
  for (llvm::StringRef step : idr::pipelineSteps()) {
    ++index;
    if (checkOnly && stepName(step) == "idr-lower")
      return ok;
    if (omitted.contains(stepName(step)))
      continue;
    std::string text = step.str();
    if (stepName(step) == "idr-rc") {
      llvm::SmallVector<std::string> options;
      for (const char *mechanism : {"reuse", "borrow", "sink"})
        if (omitted.contains(mechanism))
          options.push_back(std::string(mechanism) + "=false");
      if (!options.empty())
        text = "idr-rc{" + llvm::join(options, " ") + "}";
    }
    if (stepName(step) == "idr-demand" && !demand.empty())
      text = "idr-demand{promises=in-place}";
    mlir::PassManager pm(&context);
    if (!configure(pm))
      return usage;
    if (mlir::failed(mlir::parsePassPipeline(text, pm))) {
      Report() << "internal error: bad pipeline step " << text;
      return failure;
    }
    bool ran = mlir::succeeded(pm.run(*module));
    if (!ran || verdict.errors) {
      if (!verdict.rejected)
        Report() << "internal error: step " << index << " (" << step << ") "
                 << (ran ? "reported an error" : "failed");
      return status(verdict);
    }
    if (!dump(*module, index, stepName(step)))
      return failure;
  }
  if (emitKind == "mlir")
    return writeOutput([&](llvm::raw_ostream &os) {
             module->print(os);
             return true;
           })
               ? ok
               : failure;

  // Step 11: LLVM IR, joined with the runtime into one module; every symbol
  // but main internalized; LLVM's O3 pipeline; object code for the CPU. Each
  // stage has a timer of its own, so --timing says which one a compilation
  // spends its time on.
  mlir::TimingScope llvmTiming = rootTiming.nest("LLVM");
  mlir::TimingScope stage = llvmTiming.nest("translate");
  auto moduleTarget =
      (*module)->getAttrOfType<mlir::LLVM::TargetAttr>(mlir::LLVM::LLVMDialect::getTargetAttrName());
  if (!moduleTarget) {
    Report() << "internal error: the module lost its #llvm.target";
    return failure;
  }
  std::string features =
      moduleTarget.getFeatures() ? moduleTarget.getFeatures().getFeaturesString() : "";
  std::unique_ptr<llvm::TargetMachine> machine = idr::target::machine(
      *target, triple, moduleTarget.getChip().getValue(), features);
  if (!machine) {
    Report() << "internal error: no target machine for " << targetTriple;
    return failure;
  }

  llvm::LLVMContext llvmContext;
  std::unique_ptr<llvm::Module> llvmModule = mlir::translateModuleToLLVMIR(*module, llvmContext);
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

  stage = llvmTiming.nest("link runtime");
  if (!linkRuntime(*llvmModule, *target, triple, *machine))
    return failure;
  retarget(*llvmModule, *machine);
  // The program is whole, so nothing but the process entry is visible
  // outside it; O3 then removes what main does not reach. The runtime's
  // available_externally bodies stay as they are: a declaration with a body.
  llvm::internalizeModule(*llvmModule,
                          [](const llvm::GlobalValue &value) { return value.getName() == "main"; });
  stage = llvmTiming.nest("optimize");
  idr::target::optimize(*llvmModule, *machine);
  stage = llvmTiming.nest("codegen");

  if (emitKind == "llvm")
    return writeOutput([&](llvm::raw_ostream &os) {
             llvmModule->print(os, nullptr);
             return true;
           })
               ? ok
               : failure;
  return emit(*llvmModule, *machine,
              emitKind == "asm" ? llvm::CodeGenFileType::AssemblyFile
                                : llvm::CodeGenFileType::ObjectFile)
             ? ok
             : failure;
}

} // namespace idr::driver
