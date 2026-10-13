// The prepared runtime: one optimized module, written as native code with
// its bitcode beside or inside it.

#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Compile.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Report.h"
#include "idr/Driver/Runtime.h"
#include "idr/Target/Target.h"

#include "llvm/ADT/StringMap.h"
#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalObject.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Casting.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/MemoryBufferRef.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Triple.h"
#include "llvm/Transforms/IPO/Internalize.h"
#include "llvm/Transforms/Utils/ModuleUtils.h"

#include <memory>
#include <string>
#include <system_error>
#include <utility>

using namespace idr::driver;

// The optimized runtime's symbols, so that a program's object can name each
// one: a body it did not inline, a global an inlined body reads. Every
// local one becomes external with hidden visibility; the names are unique,
// since readRuntime's linker named the members' local symbols apart.
static bool externalize(llvm::Module &runtime) {
  for (llvm::GlobalValue &value : runtime.global_values()) {
    if (value.isDeclaration())
      continue;
    if (!llvm::isa<llvm::GlobalObject>(value) || !value.hasName()) {
      Report() << "internal error: the optimization left the runtime "
               << (value.hasName() ? "alias " : "an unnamed global ") << value.getName()
               << ", which the native half cannot name";
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

int idr::driver::prepare() {
  llvm::Triple triple(targetTriple);
  const llvm::Target *target = nativeTarget(triple);
  if (!target)
    return failure;
  // Only these formats mark a section for every link to leave out
  // (embedBufferInModule's exclusion); in any other, the bitcode would ship
  // in every executable.
  if (!runtimeBitcodeSection.empty() && !triple.isOSBinFormatELF() && !triple.isOSBinFormatCOFF()) {
    Report() << "unsupported --runtime-bitcode-section=" << runtimeBitcodeSection << ": a "
             << triple.str()
             << " object has no section every link leaves out; the bitcode goes beside the "
                "object (--runtime-bitcode-section='')";
    return usage;
  }
  std::unique_ptr<llvm::TargetMachine> machine =
      idr::target::machine(*target, triple, targetCpu, "");
  if (!machine) {
    Report() << "internal error: no target machine for " << targetTriple;
    return failure;
  }
  llvm::LLVMContext context;
  std::unique_ptr<llvm::Module> runtime = readRuntime(context, triple, machine->createDataLayout());
  if (!runtime)
    return failure;
  if (isPrepared(*runtime)) {
    Report() << "runtime " << runtimePath
             << " is prepared already; --prepare-runtime reads the archive";
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
  // Programs reach the C ABI and nothing else.
  llvm::internalizeModule(*runtime, [](const llvm::GlobalValue &value) {
    return value.getName().starts_with("idris_rt_");
  });
  idr::target::optimize(*runtime, *machine);
  for (const llvm::Function &function : *runtime)
    if (!function.isDeclaration() &&
        (!function.hasFnAttribute(cpuMark) || !function.hasFnAttribute(featuresMark))) {
      Report() << "internal error: the optimization made the runtime function " << function.getName()
               << " without the marks of what it was compiled for";
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
  // Kept only once the object is written too.
  std::unique_ptr<llvm::ToolOutputFile> beside;
  if (runtimeBitcodeSection.empty()) {
    std::error_code error;
    std::string path = besideObject(outputPath);
    beside = std::make_unique<llvm::ToolOutputFile>(path, error, llvm::sys::fs::OF_None);
    if (error) {
      cannotWrite(path, error);
      return failure;
    }
    beside->os() << bitcode;
  } else {
    llvm::embedBufferInModule(*runtime, llvm::MemoryBufferRef(bitcode, "idris_rt"),
                              runtimeBitcodeSection);
  }
  if (!emit(*runtime, *machine, outputPath))
    return failure;
  if (beside)
    beside->keep();
  return ok;
}
