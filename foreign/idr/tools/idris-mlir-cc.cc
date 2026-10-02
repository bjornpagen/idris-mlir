// idris-mlir-cc: runs the pipeline in process, from idr contract text to one
// object file that, linked with the runtime's, is the whole program.

#include "idr/Idr.h"
#include "idr/Target.h"

#include "mlir/Debug/BreakpointManagers/TagBreakpointManager.h"
#include "mlir/Debug/CLOptionsSetup.h"
#include "mlir/Debug/Counter.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
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
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/BinaryFormat/Magic.h"
#include "llvm/Bitcode/BitcodeReader.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DebugInfo.h"
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
#include "llvm/Transforms/Utils/ModuleUtils.h"

#include <optional>
#include <string>
#include <vector>

#include "idris_rt.h"

#include <unistd.h>

namespace cl = llvm::cl;

namespace {

// Required unless a --print option asks only what the build decided.
cl::opt<std::string> inputPath(cl::Positional, cl::desc("<input.mlir>"));
cl::opt<std::string> outputPath("o", cl::desc("Output file (not with --check)"), cl::init(""));
// Run the idr steps, whose user errors are rejections, and write nothing.
cl::opt<bool> checkOnly("check",
                        cl::desc("Stop before idr-lower and write nothing (exit status 3 "
                                 "names a rejection)"),
                        cl::init(false));
// No compile-time evaluation.
cl::opt<bool> noEval("no-eval", cl::desc("Do not run idr-eval"), cl::init(false));
cl::list<std::string> without(
    "without", cl::CommaSeparated,
    cl::desc("Leave out these steps of the pipeline (an idr-* pass other than idr-lower) or these "
             "mechanisms of idr-rc (reuse, borrow, sink), to measure what each one is worth"));
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
// The default is the target entry's (CMakeLists.txt), and an executable
// names what an older CPU lacks (idris_rt_start). `native` is the machine
// that compiles.
cl::opt<std::string> targetCpu("cpu",
                               cl::desc("Target CPU: " IDRIS_MLIR_TARGET_CPU
                                        " (default), native, or any CPU name LLVM knows "
                                        "for the target"),
                               cl::init(IDRIS_MLIR_TARGET_CPU));
// The runtime, recorded at build time: the object --prepare-runtime wrote
// from the archive of fat LTO objects, or that archive itself. Its bitcode
// joins the program's module, and the same file is on every executable's
// link line (--print-runtime). An empty path links no runtime.
cl::opt<std::string> runtimePath("runtime",
                                 cl::desc("The runtime whose bitcode joins the program, and "
                                          "which executables link: what --prepare-runtime "
                                          "wrote, or the archive of fat LTO objects it reads "
                                          "('' for none)"),
                                 cl::init(IDRIS_MLIR_RUNTIME));
cl::opt<bool> printRuntime("print-runtime",
                           cl::desc("Print the path of the runtime --runtime names, which "
                                    "every executable links, and exit"),
                           cl::init(false));
// The runtime is the same for every program, so it is optimized and
// compiled once, at build time, and each compilation links the result: what
// it then optimizes again is the program, and the runtime code it inlines.
cl::opt<bool> prepareRuntime("prepare-runtime",
                             cl::desc("Optimize the runtime archive --runtime names once, for "
                                      "the default CPU, into the object -o: native code for "
                                      "the link line with its bitcode for inlining, which "
                                      "every compilation then links (no input file)"),
                             cl::init(false));

// Exit statuses: an internal error or a
// contract violation is 1, a usage error 2, and a rejection (a user error,
// `unsupported (<reason>)`) 3.
constexpr int ok = 0, failure = 1, usage = 2, rejected = 3;

// Code is compiled for the triple the runtime is built for (the target
// entry's), which its bitcode carries. The module records it with the CPU as its
// #llvm.target; the -o flow and tools/compile.sh link for the triple
// --print-target-triple prints.
constexpr llvm::StringLiteral targetTriple = IDRIS_MLIR_TARGET_TRIPLE;
cl::opt<bool> printTargetTriple("print-target-triple",
                                cl::desc("Print the target triple executables are linked for, "
                                         "and exit"),
                                cl::init(false));
// What other compilers need to compile for the same machine, bench/run.sh's
// C versions among them: the CPU --cpu selects, `native` resolved.
cl::opt<bool> printTargetCpu("print-target-cpu",
                             cl::desc("Print the CPU code is compiled for, and exit"),
                             cl::init(false));

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
                 << " is not a CPU that LLVM knows for " << triple.str()
                 << " (use native or an LLVM CPU name)\n";
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
    llvm::errs() << "idris-mlir-cc: runtime " << runtimePath << ": "
                 << llvm::toString(archive.takeError()) << "\n";
    return false;
  }
  llvm::Error error = llvm::Error::success();
  for (const llvm::object::Archive::Child &child : (*archive)->children(error)) {
    auto name = child.getName();
    auto buffer = child.getMemoryBufferRef();
    if (!name || !buffer) {
      llvm::errs() << "idris-mlir-cc: runtime " << runtimePath << ": unreadable member\n";
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
    llvm::errs() << "idris-mlir-cc: runtime " << runtimePath << ": "
                 << llvm::toString(std::move(error)) << "\n";
    return false;
  }
  return true;
}

// Marks on the runtime's functions, as function attributes, which survive
// optimization and go with a function into every clone of it. Two are the
// runtime's own annotations. "idris-rt-baseline" (the CPU test at a
// program's entry) keeps a function compiled for the target's baseline
// whatever the program's CPU, since it runs before anything shows that the
// CPU has more. "idris-rt-compiler" (the compile-time evaluation API) names
// a function only the compiler's evaluation child calls, natively, and no
// program: the prepared runtime has no entry for it, and what it alone sets
// (the arena) is constant there. The other two record what a function was
// compiled for, before --prepare-runtime optimizes it for the default CPU,
// so that a compilation for any CPU raises it from there (retarget).
constexpr llvm::StringLiteral baselineMark = "idris-rt-baseline";
constexpr llvm::StringLiteral compilerMark = "idris-rt-compiler";
constexpr llvm::StringLiteral cpuMark = "idris-rt-cpu";
constexpr llvm::StringLiteral featuresMark = "idris-rt-features";

void markAnnotated(llvm::Module &member) {
  const llvm::GlobalVariable *annotations = member.getNamedGlobal("llvm.global.annotations");
  auto *entries = annotations && annotations->hasInitializer()
                      ? llvm::dyn_cast<llvm::ConstantArray>(annotations->getInitializer())
                      : nullptr;
  if (!entries)
    return;
  for (const llvm::Use &entry : entries->operands()) {
    auto *fields = llvm::dyn_cast<llvm::ConstantStruct>(entry.get());
    if (!fields || fields->getNumOperands() < 2)
      continue;
    auto *function = llvm::dyn_cast<llvm::Function>(fields->getOperand(0)->stripPointerCasts());
    auto *text = llvm::dyn_cast<llvm::GlobalVariable>(fields->getOperand(1)->stripPointerCasts());
    auto *data = text && text->hasInitializer()
                     ? llvm::dyn_cast<llvm::ConstantDataArray>(text->getInitializer())
                     : nullptr;
    if (!function || !data || !data->isCString())
      continue;
    llvm::StringRef mark = data->getAsCString();
    if (mark == baselineMark || mark == compilerMark)
      function->addFnAttr(mark);
  }
}

// The runtime is constant-initialized, and its `used` markers exist
// for separate compilation only. LinkOnlyNeeded always links appending
// globals, so constructors would run in every program, and `used` would keep
// dead runtime code (and its libc calls) in every executable: constructors are
// rejected, `used` markers dropped. Annotations become marks, then are
// dropped too. Prepared bitcode passes through unchanged: it is a member
// that was prepared already.
bool prepareMember(llvm::Module &member, llvm::StringRef name) {
  if (member.getTargetTriple().str() != targetTriple) {
    llvm::errs() << "idris-mlir-cc: runtime member " << name << " is compiled for "
                 << member.getTargetTriple().str() << ", and programs for " << targetTriple
                 << "\n";
    return false;
  }
  markAnnotated(member);
  if (llvm::GlobalVariable *annotations = member.getNamedGlobal("llvm.global.annotations"))
    annotations->eraseFromParent();
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

// The prepared runtime records, as module flags, the CPU its native half is
// compiled for; a compilation reads them to decide whether that half runs
// wherever the program does.
constexpr llvm::StringLiteral preparedCpuFlag = "idris-rt-prepared-cpu";
constexpr llvm::StringLiteral preparedFeaturesFlag = "idris-rt-prepared-features";

llvm::StringRef moduleFlagString(const llvm::Module &module, llvm::StringRef flag) {
  auto *text = llvm::dyn_cast_or_null<llvm::MDString>(module.getModuleFlag(flag));
  return text ? text->getString() : llvm::StringRef();
}

bool isPrepared(const llvm::Module &module) {
  return module.getModuleFlag(preparedCpuFlag) && module.getModuleFlag(preparedFeaturesFlag);
}

// The runtime as one module, for the program's triple and data layout: the
// bitcode of the object --prepare-runtime wrote (in its .llvm.lto section,
// where a fat LTO object carries its bitcode), or the members of the archive
// joined, where a symbol two members define is an error. Its debug info
// describes the runtime's C++ sources, not the program: it is most of the
// archive's bitcode, and every program would carry it, so it goes.
std::unique_ptr<llvm::Module> readRuntime(llvm::LLVMContext &context, const llvm::Triple &triple,
                                          const llvm::DataLayout &layout) {
  auto buffer = llvm::MemoryBuffer::getFile(runtimePath, /*IsText=*/false,
                                            /*RequiresNullTerminator=*/false);
  if (!buffer) {
    llvm::errs() << "idris-mlir-cc: cannot read runtime " << runtimePath << ": "
                 << buffer.getError().message() << "\n";
    return nullptr;
  }
  std::unique_ptr<llvm::Module> runtime;
  llvm::file_magic magic = llvm::identify_magic((*buffer)->getBuffer());
  if (magic == llvm::file_magic::bitcode || magic == llvm::file_magic::elf_relocatable) {
    llvm::MemoryBufferRef bitcode = (*buffer)->getMemBufferRef();
    if (magic == llvm::file_magic::elf_relocatable) {
      auto found = llvm::object::IRObjectFile::findBitcodeInMemBuffer(bitcode);
      if (!found) {
        llvm::errs() << "idris-mlir-cc: runtime " << runtimePath
                     << " carries no bitcode; the runtime is what --prepare-runtime wrote, or "
                        "the archive it reads: "
                     << llvm::toString(found.takeError()) << "\n";
        return nullptr;
      }
      bitcode = *found;
    }
    auto module = llvm::parseBitcodeFile(bitcode, context);
    if (!module) {
      llvm::errs() << "idris-mlir-cc: runtime " << runtimePath << ": "
                   << llvm::toString(module.takeError()) << "\n";
      return nullptr;
    }
    if (!prepareMember(**module, runtimePath))
      return nullptr;
    runtime = std::move(*module);
  } else {
    std::vector<Member> members;
    if (!readMembers(**buffer, members))
      return nullptr;
    runtime = std::make_unique<llvm::Module>("idris-mlir-runtime", context);
    runtime->setTargetTriple(triple);
    runtime->setDataLayout(layout);
    llvm::Linker runtimeLinker(*runtime);
    for (const Member &member : members) {
      auto module = llvm::parseBitcodeFile(member.bitcode, context);
      if (!module) {
        llvm::errs() << "idris-mlir-cc: runtime member " << member.name << ": "
                     << llvm::toString(module.takeError()) << "\n";
        return nullptr;
      }
      if (!prepareMember(**module, member.name))
        return nullptr;
      if (runtimeLinker.linkInModule(std::move(*module))) {
        llvm::errs() << "idris-mlir-cc: runtime member " << member.name
                     << " does not link with the members before it\n";
        return nullptr;
      }
    }
  }
  llvm::StripDebugInfo(*runtime);
  return runtime;
}

// Whether the prepared runtime's native half runs wherever the program does:
// the program's CPU has every feature of the CPU that half was compiled for
// that the processor test at the program's entry can name
// (IDRIS_RT_CPU_FEATURES), so the test covers both. The runtime is prepared
// for the default CPU, so this holds for every program but one compiled for
// a smaller CPU, which compiles the runtime's bodies itself.
bool nativeRuns(const llvm::Module &runtime, const llvm::Target &target, const llvm::Triple &triple,
                const llvm::TargetMachine &machine) {
  if (!isPrepared(runtime))
    return false;
  std::unique_ptr<llvm::MCSubtargetInfo> prepared(target.createMCSubtargetInfo(
      triple, moduleFlagString(runtime, preparedCpuFlag),
      moduleFlagString(runtime, preparedFeaturesFlag)));
  const llvm::MCSubtargetInfo &program = machine.getMCSubtargetInfo();
#define IDR_FEATURE(bit, name)                                                                   \
  if (prepared->checkFeatures("+" name) && !program.checkFeatures("+" name))                     \
    return false;
  IDRIS_RT_CPU_FEATURES(IDR_FEATURE)
#undef IDR_FEATURE
  return true;
}

// The program names a symbol of the runtime only to refer to it. The
// linker binds every reference the runtime makes to a name, wherever its
// code lands, to the definition of that name the joined module has: one the
// program also defined would take the runtime's place in the runtime's own
// code, and no renaming would show it. A local symbol of either side is
// told apart by the linker, and the frontend's names are namespaced, so no
// Idris program defines one of the runtime's; a module that does is
// refused before anything is linked.
bool namesApart(const llvm::Module &program, const llvm::Module &runtime) {
  for (const llvm::GlobalValue &value : program.global_values()) {
    if (value.isDeclaration() || value.hasLocalLinkage())
      continue;
    const llvm::GlobalValue *named = runtime.getNamedValue(value.getName());
    if (!named || named->hasLocalLinkage())
      continue;
    llvm::errs() << "idris-mlir-cc: the program defines " << value.getName() << ", which the runtime "
                 << (named->isDeclaration() ? "refers to" : "defines")
                 << " too: the runtime's references would bind to the program's definition\n";
    return false;
  }
  return true;
}

// The program and the runtime become one module, linked once with
// LinkOnlyNeeded: only what the program reaches joins it. From the prepared
// runtime, when its native half runs on the program's CPU, the bodies join
// as they are, available_externally: the optimizer inlines what pays and
// drops the rest, which the link line resolves in the native half, where
// every piece of runtime state has its one definition. Otherwise (the
// archive, or a program for a smaller CPU) every body the program reaches
// becomes a definition of its own and compiles with the program, so that its
// object is the whole program and the link line's runtime goes unused.
bool linkRuntime(llvm::Module &program, const llvm::Target &target, const llvm::Triple &triple,
                 const llvm::TargetMachine &machine) {
  if (runtimePath.empty())
    return true;
  std::unique_ptr<llvm::Module> runtime =
      readRuntime(program.getContext(), program.getTargetTriple(), program.getDataLayout());
  if (!runtime || !namesApart(program, *runtime))
    return false;
  if (!nativeRuns(*runtime, target, triple, machine))
    for (llvm::GlobalValue &value : runtime->global_values())
      if (value.hasAvailableExternallyLinkage())
        value.setLinkage(llvm::GlobalValue::ExternalLinkage);
  if (llvm::Linker::linkModules(program, std::move(runtime), llvm::Linker::LinkOnlyNeeded)) {
    llvm::errs() << "idris-mlir-cc: internal error: linking the runtime into the program failed\n";
    return false;
  }
  return true;
}

// Runtime code was compiled for the target's baseline, plus the
// features a function asks for itself (a simdutf kernel's AVX2, say). It takes
// the program's CPU and keeps every feature it asked for, so it inlines into
// program code and no function loses an instruction it relies on; the
// baseline functions keep the baseline. A prepared function remembers what
// it asked for in its marks, which the archive's functions still carry as
// their attributes; the marks are read off here.
void retarget(llvm::Module &module, const llvm::TargetMachine &machine) {
  std::string cpuFeatures = machine.getTargetFeatureString().str();
  for (llvm::Function &function : module) {
    if (function.isDeclaration() || !function.hasFnAttribute("target-cpu"))
      continue;
    std::string features =
        function.getFnAttribute(function.hasFnAttribute(featuresMark) ? featuresMark
                                                                      : "target-features")
            .getValueAsString()
            .str();
    function.removeFnAttr(cpuMark);
    function.removeFnAttr(featuresMark);
    if (function.hasFnAttribute(baselineMark))
      continue;
    if (!cpuFeatures.empty())
      features = features.empty() ? cpuFeatures : cpuFeatures + "," + features;
    function.addFnAttr("target-cpu", machine.getTargetCPU());
    function.removeFnAttr("tune-cpu");
    if (features.empty())
      function.removeFnAttr("target-features");
    else
      function.addFnAttr("target-features", features);
  }
}

// Machine code for the module, of the kind --emit asks, into the output file.
bool emit(llvm::Module &module, llvm::TargetMachine &machine, llvm::CodeGenFileType fileType) {
  return writeOutput([&](llvm::raw_ostream &os) {
    auto *pwrite = static_cast<llvm::raw_pwrite_stream *>(&os);
    llvm::legacy::PassManager codegen;
    if (machine.addPassesToEmitFile(codegen, *pwrite, nullptr, fileType)) {
      llvm::errs() << "idris-mlir-cc: the target cannot emit object files\n";
      return false;
    }
    codegen.run(module);
    return true;
  });
}

// The optimized runtime's symbols, so that a program's object can name each
// one: a body it did not inline, a global an inlined body reads. Every
// local one becomes external with hidden visibility; the names are unique,
// since readRuntime's linker named the members' local symbols apart.
bool externalize(llvm::Module &runtime) {
  for (llvm::GlobalValue &value : runtime.global_values()) {
    if (value.isDeclaration())
      continue;
    if (!llvm::isa<llvm::GlobalObject>(value) || !value.hasName()) {
      llvm::errs() << "idris-mlir-cc: internal error: the optimization left the runtime "
                   << (value.hasName() ? "alias " : "an unnamed global ") << value.getName()
                   << ", which the native half cannot name\n";
      return false;
    }
    if (value.hasLocalLinkage()) {
      value.setLinkage(llvm::GlobalValue::ExternalLinkage);
      value.setVisibility(llvm::GlobalValue::HiddenVisibility);
    }
    value.setDSOLocal(true);
  }
  return true;
}

// --prepare-runtime: the archive's members, joined, raised to the default
// CPU and optimized as a program is, with everything but the C ABI programs
// reach (idris_rt_*, less the compiler's own entries) internal. Each
// function first records what it was compiled for, so that retarget can
// raise it to any CPU from there; the optimization copies the marks into
// every function it makes from another (a clone, a thunk), and one without
// them could not be retargeted, so none may be left.
//
// The result is one object, written as a fat LTO object is: its native code
// is what every executable's link line takes, and its .llvm.lto section
// holds the same module as bitcode with every definition available_externally,
// which is what joins each program's module (linkRuntime). The two halves
// come from the one module, so they name the same symbols: a body the
// program's optimizer inlines becomes program code, one it does not is
// dropped and resolves to the native half, and runtime state (the
// allocator's thread-locals, the output buffer, the live-cell count) is
// defined once, in the native half, whichever bodies were inlined.
int prepare(const llvm::Target &target, const llvm::Triple &triple, const Cpu &cpu) {
  if (runtimePath.empty()) {
    llvm::errs() << "idris-mlir-cc: --prepare-runtime needs --runtime to name the archive\n";
    return usage;
  }
  std::unique_ptr<llvm::TargetMachine> machine(
      target.createTargetMachine(triple, cpu.name, cpu.features, idr::targetOptions(),
                                 llvm::Reloc::PIC_, std::nullopt, llvm::CodeGenOptLevel::Aggressive));
  if (!machine) {
    llvm::errs() << "idris-mlir-cc: internal error: no target machine for " << targetTriple
                 << "\n";
    return failure;
  }
  llvm::LLVMContext context;
  std::unique_ptr<llvm::Module> runtime = readRuntime(context, triple, machine->createDataLayout());
  if (!runtime)
    return failure;
  if (isPrepared(*runtime)) {
    llvm::errs() << "idris-mlir-cc: runtime " << runtimePath
                 << " is prepared already; --prepare-runtime reads the archive\n";
    return usage;
  }
  llvm::StringMap<std::pair<std::string, std::string>> compiledFor;
  for (const llvm::Function &function : *runtime)
    if (!function.isDeclaration())
      compiledFor[function.getName()] = {
          function.getFnAttribute("target-cpu").getValueAsString().str(),
          function.getFnAttribute("target-features").getValueAsString().str()};
  retarget(*runtime, *machine);
  for (llvm::Function &function : *runtime)
    if (auto found = compiledFor.find(function.getName()); found != compiledFor.end()) {
      function.addFnAttr(cpuMark, found->second.first);
      function.addFnAttr(featuresMark, found->second.second);
    }
  // Programs reach the C ABI, but the compiler's part of it.
  llvm::internalizeModule(*runtime, [](const llvm::GlobalValue &value) {
    auto *function = llvm::dyn_cast<llvm::Function>(&value);
    return value.getName().starts_with("idris_rt_") &&
           !(function && function->hasFnAttribute(compilerMark));
  });
  idr::optimize(*runtime, *machine);
  for (const llvm::Function &function : *runtime)
    if (!function.isDeclaration() &&
        (!function.hasFnAttribute(cpuMark) || !function.hasFnAttribute(featuresMark))) {
      llvm::errs() << "idris-mlir-cc: internal error: the optimization made the runtime function "
                   << function.getName() << " without the marks of what it was compiled for\n";
      return failure;
    }
  if (!externalize(*runtime))
    return failure;
  runtime->addModuleFlag(llvm::Module::Error, preparedCpuFlag,
                         llvm::MDString::get(context, machine->getTargetCPU()));
  runtime->addModuleFlag(llvm::Module::Error, preparedFeaturesFlag,
                         llvm::MDString::get(context, machine->getTargetFeatureString()));
  // The bitcode half: the same module, every definition available_externally.
  std::string bitcode;
  {
    for (llvm::GlobalValue &value : runtime->global_values())
      if (!value.isDeclaration())
        value.setLinkage(llvm::GlobalValue::AvailableExternallyLinkage);
    llvm::raw_string_ostream os(bitcode);
    llvm::WriteBitcodeToFile(*runtime, os);
    for (llvm::GlobalValue &value : runtime->global_values())
      if (value.hasAvailableExternallyLinkage())
        value.setLinkage(llvm::GlobalValue::ExternalLinkage);
  }
  llvm::embedBufferInModule(*runtime, llvm::MemoryBufferRef(bitcode, "idris_rt"), ".llvm.lto");
  return emit(*runtime, *machine, llvm::CodeGenFileType::ObjectFile) ? ok : failure;
}

// Which errors the passes reported: a rejection (`unsupported (<reason>):
// ...`) is the user's, at the location of the user's code the frontend
// reports; any other error is internal.
struct Verdict {
  bool rejected = false;
};

int status(const Verdict &verdict) { return verdict.rejected ? rejected : failure; }

// The module's target (idr-target), which every step reads: idr-eval's JIT
// compiles for its CPU, so what compile-time evaluation spends does not
// depend on the machine that compiles; idr-lower tells the runtime's entry
// which of its features to test; the object code is compiled for it.
mlir::LogicalResult setTarget(mlir::ModuleOp module, const Cpu &cpu) {
  mlir::PassManager pm(module.getContext());
  pm.addPass(idr::createIdrTarget(idr::IdrTargetOptions{cpu.name, cpu.features}));
  return pm.run(module);
}

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
    llvm::errs() << "idris-mlir-cc: --emit must be obj, asm, llvm or mlir\n";
    return usage;
  }
  if (checkOnly == !outputPath.empty()) {
    llvm::errs() << "idris-mlir-cc: give either -o or --check\n";
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
    llvm::errs() << "idris-mlir-cc: " << error << "\n";
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
      std::string message = diagnostic.str();
      if (llvm::StringRef(message).starts_with("unsupported ("))
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
  if (mlir::failed(setTarget(*module, *cpu))) {
    llvm::errs() << "idris-mlir-cc: internal error: the module's target could not be set\n";
    return failure;
  }

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

  // --without: the names must be steps or idr-rc mechanisms, so that a
  // misspelling measures nothing by accident.
  llvm::StringSet<> omitted;
  for (const std::string &name : without) {
    bool mechanism = name == "reuse" || name == "borrow" || name == "sink";
    bool step = name != "idr-lower" && llvm::StringRef(name).starts_with("idr-") &&
                llvm::any_of(idr::pipelineSteps(),
                             [&](llvm::StringRef s) { return stepName(s) == name; });
    if (!mechanism && !step) {
      llvm::errs() << "idris-mlir-cc: --without names " << name
                   << ", which is neither a pipeline step nor reuse, borrow or sink\n";
      return usage;
    }
    omitted.insert(name);
  }
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
    mlir::PassManager pm(&context);
    if (statistics)
      pm.enableStatistics(mlir::PassDisplayMode::List);
    // MLIR's pass manager options, on every pass manager.
    if (mlir::failed(mlir::applyPassManagerCLOptions(pm)))
      return usage;
    pm.enableTiming(rootTiming);
    if (mlir::failed(mlir::parsePassPipeline(text, pm))) {
      llvm::errs() << "idris-mlir-cc: internal error: bad pipeline step " << text << "\n";
      return failure;
    }
    if (mlir::failed(pm.run(*module))) {
      if (!verdict.rejected)
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
  // but main internalized; LLVM's O3 pipeline; object code for the CPU. Each
  // stage has a timer of its own, so --timing says which one a compilation
  // spends its time on.
  mlir::TimingScope llvmTiming = rootTiming.nest("LLVM");
  mlir::TimingScope stage = llvmTiming.nest("translate");
  auto moduleTarget =
      (*module)->getAttrOfType<mlir::LLVM::TargetAttr>(mlir::LLVM::LLVMDialect::getTargetAttrName());
  if (!moduleTarget) {
    llvm::errs() << "idris-mlir-cc: internal error: the module lost its #llvm.target\n";
    return failure;
  }
  std::string features =
      moduleTarget.getFeatures() ? moduleTarget.getFeatures().getFeaturesString() : "";
  std::unique_ptr<llvm::TargetMachine> machine(target->createTargetMachine(
      triple, moduleTarget.getChip().getValue(), features, idr::targetOptions(), llvm::Reloc::PIC_,
      std::nullopt, llvm::CodeGenOptLevel::Aggressive));
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
  idr::optimize(*llvmModule, *machine);
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

// The compilation runs on the runtime's reserved-stack runner, on a stack
// as large as the address space allows, committed as it is touched: MLIR's
// parser, printer and walks recurse over nested constants, and compile-time
// evaluation builds them as large as the program's own values (no limits
// but the machine's). PIN(mlir-recursion) — see PINS.md
struct Compilation {
  int status = failure;
};

void compile(void *argument) { static_cast<Compilation *>(argument)->status = run(); }

// From the signal handler: only write and _exit.
[[noreturn]] void compilationExhausted() {
  static constexpr char message[] =
      "idris-mlir-cc: internal error: the compilation exhausted its stack\n";
  (void)!write(2, message, sizeof message - 1);
  _exit(failure);
}

int runOnLargeStack() {
  Compilation compilation;
  if (idris_rt_run_on_stack(compile, &compilation, size_t{1} << 44, size_t{1} << 20,
                            compilationExhausted) != 0) {
    llvm::errs() << "idris-mlir-cc: no stack could be reserved for the compilation\n";
    return failure;
  }
  return compilation.status;
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
  if (printTargetTriple) {
    llvm::outs() << targetTriple << "\n";
    return ok;
  }
  if (printTargetCpu) {
    llvm::outs() << (targetCpu == "native" ? llvm::sys::getHostCPUName().str() : targetCpu)
                 << "\n";
    return ok;
  }
  if (printRuntime) {
    llvm::outs() << runtimePath << "\n";
    return ok;
  }
  if (inputPath.empty() != prepareRuntime) {
    llvm::errs() << (prepareRuntime ? "idris-mlir-cc: --prepare-runtime takes no input file\n"
                                    : "idris-mlir-cc: no input file (see --help)\n");
    return usage;
  }
  return runOnLargeStack();
}
