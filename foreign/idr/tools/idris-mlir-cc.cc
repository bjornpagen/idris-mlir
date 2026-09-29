// idris-mlir-cc: runs the pipeline in process, from idr contract text to one
// object file that holds the whole program.

#include "idr/Idr.h"
#include "idr/Target.h"

#include "mlir/Debug/BreakpointManagers/TagBreakpointManager.h"
#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/Debug/Counter.h"
#include "mlir/IR/AsmState.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Remarks.h"
#include "mlir/InitAllDialects.h"
#include "mlir/InitAllExtensions.h"
#include "mlir/InitAllPasses.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Remark/RemarkStreamer.h"
#include "mlir/Support/FileUtilities.h"
#include "mlir/Support/Timing.h"
#include "mlir/Target/LLVMIR/Dialect/Builtin/BuiltinToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Dialect/LLVMIR/LLVMToLLVMIRTranslation.h"
#include "mlir/Target/LLVMIR/Export.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Module.h"
#include "llvm/Linker/Linker.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Object/Archive.h"
#include "llvm/Object/IRObjectFile.h"
#include "llvm/Remarks/RemarkFormat.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/InitLLVM.h"
#include "llvm/Support/MemoryBuffer.h"
#include "llvm/Support/Path.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/Target/TargetOptions.h"
#include "llvm/TargetParser/Host.h"
#include "llvm/TargetParser/Triple.h"
#include "llvm/Transforms/IPO/Internalize.h"

#include <optional>
#include <string>
#include <vector>

#include <pthread.h>
#include <sys/mman.h>

namespace cl = llvm::cl;

namespace {

cl::opt<std::string> inputPath(cl::Positional, cl::desc("<input.mlir>"), cl::Required);
cl::opt<std::string> outputPath("o", cl::desc("Output file (not with --check)"), cl::init(""));
// Run the idr steps, whose user errors are rejections, and write nothing.
cl::opt<bool> checkOnly("check",
                        cl::desc("Stop before idr-lower and write nothing (exit status 3 "
                                 "names a rejection)"),
                        cl::init(false));
// No compile-time evaluation.
cl::opt<bool> noEval("no-eval", cl::desc("Do not run idr-eval"), cl::init(false));
cl::opt<std::string> remarks("remarks",
                             cl::desc("Print the remarks (passed, missed, failed and analysis) "
                                      "of these categories (a regex), e.g. idr-eval"),
                             cl::init(""));
cl::opt<std::string> remarksFile("remarks-file",
                                 cl::desc("Write the remarks of the categories --remarks names, "
                                          "or of every category without it, to this YAML file"),
                                 cl::init(""));
// Which actions -log-actions-to logs: otherwise every one, each pass
// execution with the whole module.
cl::list<std::string> logActionsTags(
    "log-actions-tags",
    cl::desc("With -log-actions-to, log only the actions of these tags, e.g. idr-eval-call"),
    cl::CommaSeparated);
cl::opt<bool> timing("timing", cl::desc("Report the time of each pass and LLVM stage"),
                     cl::init(false));
cl::opt<std::string> emitKind("emit", cl::desc("obj (default), asm, llvm or mlir"),
                              cl::init("obj"));
cl::opt<std::string> dumpAfter("dump-after",
                               cl::desc("Dump the module after this step, or 'all'"),
                               cl::init(""));
cl::opt<std::string> dumpDir("dump-dir", cl::desc("Directory for --dump-after files"),
                             cl::init("."));
// x86-64-v3 (AVX2, BMI2, FMA) runs on every x86-64 CPU since
// Haswell (2013) and AMD's Zen. `native` is the machine that compiles,
// `x86-64` the baseline.
cl::opt<std::string> targetCpu("cpu",
                               cl::desc("Target CPU: x86-64-v3 (default), native, x86-64, "
                                        "or any x86-64 CPU name LLVM knows"),
                               cl::init("x86-64-v3"));
// The runtime's archive of fat LTO objects, recorded at build time.
// Its bitcode joins the program's module; an empty path links no runtime.
cl::opt<std::string> runtimeArchive("runtime",
                                    cl::desc("Runtime archive of fat LTO objects whose bitcode "
                                             "joins the program ('' for none)"),
                                    cl::init(IDRIS_MLIR_RUNTIME_ARCHIVE));

// Exit statuses: an internal error or a
// contract violation is 1, a usage error 2, a profile rejection (a user
// error, `unsupported (<reason>)`) 3, and a total evaluation the machine
// cannot finish 4.
constexpr int ok = 0, failure = 1, usage = 2, rejected = 3, exhausted = 4;

// Executables are static-PIE on musl, so code is compiled for the
// musl triple, the one the runtime's bitcode carries.
constexpr llvm::StringLiteral targetTriple = "x86_64-unknown-linux-musl";

std::string stepName(llvm::StringRef step) {
  std::string name = step.split(',').first.str();
  return name;
}

bool dump(mlir::ModuleOp module, unsigned index, llvm::StringRef name) {
  if (dumpAfter.empty() || (dumpAfter != "all" && dumpAfter != name))
    return true;
  llvm::SmallString<128> path(dumpDir);
  llvm::sys::path::append(path, llvm::formatv("{0:02}-{1}.mlir", index, name).str());
  std::error_code error;
  llvm::raw_fd_ostream out(path, error);
  if (error) {
    llvm::errs() << "idris-mlir-cc: cannot write " << path << ": " << error.message() << "\n";
    return false;
  }
  module->print(out, mlir::OpPrintingFlags().enableDebugInfo());
  return true;
}

// Writes `contents` to the output path only once everything succeeded, so a
// failure never leaves a partial or stale output.
template <typename Write> bool writeOutput(Write write) {
  std::error_code error;
  auto file = std::make_unique<llvm::ToolOutputFile>(outputPath, error, llvm::sys::fs::OF_None);
  if (error) {
    llvm::errs() << "idris-mlir-cc: cannot write " << outputPath << ": " << error.message() << "\n";
    return false;
  }
  if (!write(file->os()))
    return false;
  file->keep();
  return true;
}

// The CPU and extra features for --cpu. A name LLVM does not
// know is a usage error: LLVM itself would only warn and fall back to a
// generic CPU.
struct Cpu {
  std::string name;
  std::string features;
};

std::optional<Cpu> selectCpu(const llvm::Target &target, const llvm::Triple &triple) {
  Cpu cpu{targetCpu, ""};
  if (cpu.name == "native") {
    cpu.name = llvm::sys::getHostCPUName().str();
    std::vector<std::string> features;
    for (const auto &feature : llvm::sys::getHostCPUFeatures())
      features.push_back((feature.getValue() ? "+" : "-") + feature.getKey().str());
    llvm::sort(features);
    cpu.features = llvm::join(features, ",");
  }
  std::unique_ptr<llvm::MCSubtargetInfo> subtarget(
      target.createMCSubtargetInfo(triple, cpu.name, cpu.features));
  if (!subtarget || !subtarget->isCPUStringValid(cpu.name)) {
    llvm::errs() << "idris-mlir-cc: unsupported --cpu=" << targetCpu << ": " << cpu.name
                 << " is not an x86-64 CPU that LLVM knows (use native, x86-64, "
                    "x86-64-v2, x86-64-v3, x86-64-v4 or an LLVM CPU name)\n";
    return std::nullopt;
  }
  return cpu;
}

struct Member {
  std::string name;
  llvm::MemoryBufferRef bitcode;
};

// Every member of the runtime archive is a fat LTO object; this is
// the bitcode half of each.
bool readMembers(const llvm::MemoryBuffer &archiveBuffer, std::vector<Member> &members) {
  auto archive = llvm::object::Archive::create(archiveBuffer.getMemBufferRef());
  if (!archive) {
    llvm::errs() << "idris-mlir-cc: runtime " << runtimeArchive << ": "
                 << llvm::toString(archive.takeError()) << "\n";
    return false;
  }
  llvm::Error error = llvm::Error::success();
  for (const llvm::object::Archive::Child &child : (*archive)->children(error)) {
    auto name = child.getName();
    auto buffer = child.getMemoryBufferRef();
    if (!name || !buffer) {
      llvm::errs() << "idris-mlir-cc: runtime " << runtimeArchive << ": unreadable member\n";
      llvm::consumeError(name.takeError());
      llvm::consumeError(buffer.takeError());
      llvm::consumeError(std::move(error));
      return false;
    }
    auto bitcode = llvm::object::IRObjectFile::findBitcodeInMemBuffer(*buffer);
    if (!bitcode) {
      llvm::errs() << "idris-mlir-cc: runtime member " << *name
                   << " carries no bitcode; the runtime must be built of fat LTO objects: "
                   << llvm::toString(bitcode.takeError()) << "\n";
      llvm::consumeError(std::move(error));
      return false;
    }
    members.push_back({name->str(), *bitcode});
  }
  if (error) {
    llvm::errs() << "idris-mlir-cc: runtime " << runtimeArchive << ": "
                 << llvm::toString(std::move(error)) << "\n";
    return false;
  }
  return true;
}

// The runtime is constant-initialized, and its `used` markers exist
// for separate compilation only. LinkOnlyNeeded always links appending
// globals, so constructors would run in every program, and `used` would keep
// dead runtime code (and its libc calls) in every executable: constructors are
// rejected, `used` markers dropped.
bool prepareMember(llvm::Module &member, llvm::StringRef name) {
  // An empty list of constructors, which clang writes for some translation
  // units, lists none.
  for (llvm::StringRef array : {"llvm.global_ctors", "llvm.global_dtors"})
    if (llvm::GlobalVariable *global = member.getNamedGlobal(array)) {
      if (llvm::cast<llvm::ArrayType>(global->getValueType())->getNumElements() == 0) {
        global->eraseFromParent();
        continue;
      }
      llvm::errs() << "idris-mlir-cc: runtime member " << name
                   << " has static constructors or destructors; the runtime must be "
                      "constant-initialized\n";
      return false;
    }
  for (llvm::StringRef array : {"llvm.used", "llvm.compiler.used"})
    if (llvm::GlobalVariable *global = member.getNamedGlobal(array))
      global->eraseFromParent();
  for (const llvm::GlobalVariable &global : member.globals())
    if (global.hasAppendingLinkage()) {
      llvm::errs() << "idris-mlir-cc: unsupported (runtime): runtime member " << name
                   << " defines the appending global " << global.getName() << "\n";
      return false;
    }
  return true;
}

// The program and the runtime become one module. The members are
// first joined into one runtime module, where a symbol two members define is
// an error, and that module is linked once with LinkOnlyNeeded: only what the
// program reaches joins it, and each file-local global is copied at most
// once, so no runtime state is ever split in two.
bool linkRuntime(llvm::Module &program) {
  if (runtimeArchive.empty())
    return true;
  auto archiveBuffer = llvm::MemoryBuffer::getFile(runtimeArchive, /*IsText=*/false,
                                                   /*RequiresNullTerminator=*/false);
  if (!archiveBuffer) {
    llvm::errs() << "idris-mlir-cc: cannot read runtime " << runtimeArchive << ": "
                 << archiveBuffer.getError().message() << "\n";
    return false;
  }
  std::vector<Member> members;
  if (!readMembers(**archiveBuffer, members))
    return false;
  auto runtime = std::make_unique<llvm::Module>("idris-mlir-runtime", program.getContext());
  runtime->setTargetTriple(program.getTargetTriple());
  runtime->setDataLayout(program.getDataLayout());
  llvm::Linker runtimeLinker(*runtime);
  for (const Member &member : members) {
    auto module = llvm::parseBitcodeFile(member.bitcode, program.getContext());
    if (!module) {
      llvm::errs() << "idris-mlir-cc: runtime member " << member.name << ": "
                   << llvm::toString(module.takeError()) << "\n";
      return false;
    }
    if (!prepareMember(**module, member.name))
      return false;
    if (runtimeLinker.linkInModule(std::move(*module))) {
      llvm::errs() << "idris-mlir-cc: runtime member " << member.name
                   << " does not link with the members before it\n";
      return false;
    }
  }
  if (llvm::Linker::linkModules(program, std::move(runtime), llvm::Linker::LinkOnlyNeeded)) {
    llvm::errs() << "idris-mlir-cc: internal error: linking the runtime into the program failed\n";
    return false;
  }
  return true;
}

// Runtime code was compiled for the x86-64 baseline, plus the
// features a function asks for itself (a simdutf kernel's AVX2, say). It takes
// the program's CPU and keeps every feature it asked for, so it inlines into
// program code and no function loses an instruction it relies on.
void retarget(llvm::Module &module, const llvm::TargetMachine &machine) {
  std::string cpuFeatures = machine.getTargetFeatureString().str();
  for (llvm::Function &function : module) {
    if (function.isDeclaration() || !function.hasFnAttribute("target-cpu"))
      continue;
    std::string features = function.getFnAttribute("target-features").getValueAsString().str();
    if (!cpuFeatures.empty())
      features = features.empty() ? cpuFeatures : cpuFeatures + "," + features;
    function.addFnAttr("target-cpu", machine.getTargetCPU());
    function.removeFnAttr("tune-cpu");
    if (!features.empty())
      function.addFnAttr("target-features", features);
  }
}

// Which errors the passes reported: a profile rejection (`unsupported
// (<reason>): ...`) and an evaluation the machine cannot finish (`unsupported
// (compile-time evaluation): ...`) are the user's, each at the location of the user's code
// the frontend reports; any other error is internal.
struct Verdict {
  bool rejected = false;
  bool exhausted = false;
};

int status(const Verdict &verdict) {
  return verdict.exhausted ? exhausted : verdict.rejected ? rejected : failure;
}

int run() {
  mlir::registerAllPasses();
  idr::registerIdrPipeline();
  // The program is parsed with exactly the contract's
  // dialects, so an op of any other fails to parse. The rest load after.
  mlir::DialectRegistry contract;
  contract.insert<mlir::func::FuncDialect, mlir::arith::ArithDialect, mlir::math::MathDialect,
                  mlir::ub::UBDialect>();
  idr::registerIdr(contract);
  mlir::MLIRContext context(contract);
  // MLIR runs single-threaded, so results do not depend on
  // scheduling, and idr-eval may fork.
  context.disableMultithreading();

  if (emitKind != "obj" && emitKind != "asm" && emitKind != "llvm" && emitKind != "mlir") {
    llvm::errs() << "idris-mlir-cc: --emit must be obj, asm, llvm or mlir\n";
    return usage;
  }
  if (checkOnly == !outputPath.empty()) {
    llvm::errs() << "idris-mlir-cc: give either -o or --check\n";
    return usage;
  }
  llvm::InitializeNativeTarget();
  llvm::InitializeNativeTargetAsmPrinter();
  llvm::Triple triple(targetTriple);
  std::string error;
  const llvm::Target *target = llvm::TargetRegistry::lookupTarget(triple, error);
  if (!target) {
    llvm::errs() << "idris-mlir-cc: " << error << "\n";
    return failure;
  }
  std::optional<Cpu> cpu = selectCpu(*target, triple);
  if (!cpu)
    return usage;

  llvm::SourceMgr sources;
  mlir::SourceMgrDiagnosticHandler diagnostics(sources, &context);
  Verdict verdict;
  context.getDiagEngine().registerHandler([&](mlir::Diagnostic &diagnostic) {
    if (diagnostic.getSeverity() == mlir::DiagnosticSeverity::Error) {
      std::string message = diagnostic.str();
      if (llvm::StringRef(message).starts_with("unsupported (compile-time evaluation)"))
        verdict.exhausted = true;
      else if (llvm::StringRef(message).starts_with("unsupported ("))
        verdict.rejected = true;
    }
    return mlir::failure();
  });
  mlir::OwningOpRef<mlir::ModuleOp> module =
      mlir::parseSourceFile<mlir::ModuleOp>(inputPath, sources, &context);
  if (!module)
    return failure;
  mlir::DialectRegistry everything;
  mlir::registerAllDialects(everything);
  mlir::registerAllExtensions(everything);
  mlir::registerBuiltinDialectTranslation(everything);
  mlir::registerLLVMDialectTranslation(everything);
  context.appendDialectRegistry(everything);

  // --remarks prints the remarks of its categories, of every kind;
  // --remarks-file streams them, or every remark, to a YAML file.
  if (!remarks.empty() || !remarksFile.empty()) {
    std::unique_ptr<mlir::remark::detail::MLIRRemarkStreamerBase> streamer;
    if (!remarksFile.empty()) {
      auto file = mlir::remark::detail::LLVMRemarkStreamer::createToFile(
          remarksFile, llvm::remarks::Format::YAML);
      if (mlir::failed(file)) {
        llvm::errs() << "idris-mlir-cc: cannot write the remarks to " << remarksFile << "\n";
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

  unsigned index = 0;
  for (llvm::StringRef step : idr::pipelineSteps()) {
    ++index;
    if (checkOnly && stepName(step) == "idr-lower")
      return ok;
    mlir::PassManager pm(&context);
    if (statistics)
      pm.enableStatistics(mlir::PassDisplayMode::List);
    // MLIR's pass manager options, on every pass manager.
    if (mlir::failed(mlir::applyPassManagerCLOptions(pm)))
      return usage;
    pm.enableTiming(rootTiming);
    if (mlir::failed(mlir::parsePassPipeline(step, pm))) {
      llvm::errs() << "idris-mlir-cc: internal error: bad pipeline step " << step << "\n";
      return failure;
    }
    if (mlir::failed(pm.run(*module))) {
      if (!verdict.rejected && !verdict.exhausted)
        llvm::errs() << "idris-mlir-cc: internal error: step " << index << " (" << step
                     << ") failed\n";
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
  // but main internalized; LLVM's O3 pipeline; object code for the CPU.
  mlir::TimingScope llvmTiming = rootTiming.nest("LLVM");
  std::unique_ptr<llvm::TargetMachine> machine(target->createTargetMachine(
      triple, cpu->name, cpu->features, idr::targetOptions(), llvm::Reloc::PIC_, std::nullopt,
      llvm::CodeGenOptLevel::Aggressive));
  if (!machine) {
    llvm::errs() << "idris-mlir-cc: internal error: no target machine for " << targetTriple
                 << "\n";
    return failure;
  }

  llvm::LLVMContext llvmContext;
  std::unique_ptr<llvm::Module> llvmModule = mlir::translateModuleToLLVMIR(*module, llvmContext);
  if (!llvmModule) {
    llvm::errs() << "idris-mlir-cc: internal error: translation to LLVM IR failed\n";
    return failure;
  }
  llvmModule->setTargetTriple(triple);
  llvmModule->setDataLayout(machine->createDataLayout());
  // The executable is static-PIE.
  llvmModule->setPICLevel(llvm::PICLevel::BigPIC);
  llvmModule->setPIELevel(llvm::PIELevel::Large);

  if (!linkRuntime(*llvmModule))
    return failure;
  retarget(*llvmModule, *machine);
  // The program is whole, so nothing but the process entry is
  // visible outside it; O3 then removes what main does not reach.
  llvm::internalizeModule(*llvmModule,
                          [](const llvm::GlobalValue &value) { return value.getName() == "main"; });
  idr::optimize(*llvmModule, *machine);

  if (emitKind == "llvm")
    return writeOutput([&](llvm::raw_ostream &os) {
             llvmModule->print(os, nullptr);
             return true;
           })
               ? ok
               : failure;
  auto fileType = emitKind == "asm" ? llvm::CodeGenFileType::AssemblyFile
                                    : llvm::CodeGenFileType::ObjectFile;
  return writeOutput([&](llvm::raw_ostream &os) {
           auto *pwrite = static_cast<llvm::raw_pwrite_stream *>(&os);
           llvm::legacy::PassManager codegen;
           if (machine->addPassesToEmitFile(codegen, *pwrite, nullptr, fileType)) {
             llvm::errs() << "idris-mlir-cc: the target cannot emit object files\n";
             return false;
           }
           codegen.run(*llvmModule);
           return true;
         })
             ? ok
             : failure;
}

// The compilation runs on a stack reserved as large as the address space
// allows, committed as it is touched: MLIR's parser, printer and walks
// recurse over nested constants, and compile-time evaluation builds them as
// large as the program's own values (no limits but the machine's).
struct Compilation {
  int status = failure;
};

void *compile(void *argument) {
  static_cast<Compilation *>(argument)->status = run();
  return nullptr;
}

int runOnLargeStack() {
  Compilation compilation;
  constexpr size_t guard = size_t{1} << 20;
  for (size_t size = size_t{1} << 44; size >= size_t{1} << 26; size >>= 1) {
    void *base = mmap(nullptr, size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (base == MAP_FAILED)
      continue;
    pthread_attr_t attributes;
    pthread_t thread;
    if (mprotect(base, guard, PROT_NONE) != 0 || pthread_attr_init(&attributes) != 0 ||
        pthread_attr_setstack(&attributes, static_cast<char *>(base) + guard, size - guard) != 0 ||
        pthread_create(&thread, &attributes, compile, &compilation) != 0 ||
        pthread_join(thread, nullptr) != 0) {
      munmap(base, size);
      continue;
    }
    return compilation.status;
  }
  llvm::errs() << "idris-mlir-cc: no stack could be reserved for the compilation\n";
  return failure;
}

} // namespace

int main(int argc, char **argv) {
  llvm::InitLLVM init(argc, argv);
  // MLIR's own options, as mlir-opt has them: the pass manager's (IR
  // printing, statistics, crash reproducers), timing, the context's, the
  // printer's, action logging and debug counters.
  mlir::registerAsmPrinterCLOptions();
  mlir::registerMLIRContextCLOptions();
  mlir::registerPassManagerCLOptions();
  mlir::registerDefaultTimingManagerCLOptions();
  mlir::tracing::DebugConfig::registerCLOptions();
  mlir::tracing::DebugCounter::registerCLOptions();
  // LLVM's -stats, which LLVM prints at exit, also prints the statistics of
  // each step's passes.
  if (cl::Option *stats = cl::getRegisteredOptions().lookup("stats")) {
    stats->setDescription("Print the statistics of every pass, and LLVM's at exit");
    stats->setHiddenFlag(cl::NotHidden);
  }
  // Functions and blocks not reached by fallthrough start on a
  // 64-byte line. The padding is never executed, and the hot code of a
  // program no longer moves when unrelated code changes size. Given first,
  // so the command line can override them.
  std::vector<const char *> args(argv, argv + argc);
  args.insert(args.begin() + 1,
              {"--align-all-functions=6", "--align-all-nofallthru-blocks=6"});
  if (!cl::ParseCommandLineOptions(static_cast<int>(args.size()), args.data(),
                                   "idris-mlir-cc: idr to object code\n", &llvm::errs()))
    return usage;
  return runOnLargeStack();
}
