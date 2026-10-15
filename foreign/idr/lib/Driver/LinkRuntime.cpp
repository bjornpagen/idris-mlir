// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's bitcode linked into the program's module, and its functions
// raised to the program's CPU.

#include "idr/Driver/Report.h"
#include "idr/Driver/Runtime.h"

// The target entry's list of processor features, an X-macro.
#include "cpu_features.h"

#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/Mangler.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/Linker/Linker.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/Casting.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Triple.h"

#include <memory>
#include <optional>
#include <string>
#include <utility>

using namespace idr::driver;

// Whether the prepared runtime's native half runs wherever the program does:
// the program's CPU has every feature of the CPU that half was compiled for
// that the processor test at the program's entry can name
// (IDRIS_RT_CPU_FEATURES), so the test covers both. The build prepares the
// runtime for the CPU every program is compiled for, so this fails only for
// a runtime prepared elsewhere for a larger one, whose bodies the program
// then compiles itself.
static bool nativeRuns(const llvm::Module &runtime, const llvm::Target &target,
                       const llvm::Triple &triple, const llvm::TargetMachine &machine) {
  std::optional<PreparedFor> compiledFor = preparedFor(runtime);
  if (!compiledFor)
    return false;
  std::unique_ptr<llvm::MCSubtargetInfo> prepared(
      target.createMCSubtargetInfo(triple, compiledFor->cpu, compiledFor->features));
  const llvm::MCSubtargetInfo &program = machine.getMCSubtargetInfo();
#define IDR_FEATURE(bit, test, name)                                                             \
  if (prepared->checkFeatures("+" name) && !program.checkFeatures("+" name))                     \
    return false;
  IDRIS_RT_CPU_FEATURES(IDR_FEATURE)
#undef IDR_FEATURE
  return true;
}

// The name the linker sees for a symbol, as LLVM's Mangler writes it from the
// module's data layout: the object format's prefix before an IR name, and
// nothing before one that is already the assembly name. Two IR names can be
// one symbol: Darwin's headers give C functions their assembly names, so the
// runtime refers to write as "\01_write", which the linker reads as the
// program's "write".
static std::string linkerName(const llvm::GlobalValue &value) {
  llvm::SmallString<64> name;
  llvm::Mangler().getNameWithPrefix(name, &value, /*CannotUsePrivateLabel=*/false);
  return std::string(name);
}

// The program names a symbol of the runtime only to refer to it. The
// linker binds every reference the runtime makes to a name, wherever its
// code lands, to the definition of that name the joined module has: one the
// program also defined would take the runtime's place in the runtime's own
// code, and no renaming would show it. A local symbol of either side is
// told apart by the linker, and the frontend's names are namespaced, so no
// Idris program defines one of the runtime's; a module that does is
// refused before anything is linked.
static bool namesApart(const llvm::Module &program, const llvm::Module &runtime) {
  llvm::StringMap<const llvm::GlobalValue *> runtimeNames;
  for (const llvm::GlobalValue &value : runtime.global_values())
    if (!value.hasLocalLinkage())
      runtimeNames.try_emplace(linkerName(value), &value);
  for (const llvm::GlobalValue &value : program.global_values()) {
    if (value.isDeclaration() || value.hasLocalLinkage())
      continue;
    auto named = runtimeNames.find(linkerName(value));
    if (named == runtimeNames.end())
      continue;
    Report() << "the program defines " << value.getName() << ", which the runtime "
             << (named->second->isDeclaration() ? "refers to" : "defines")
             << " too: the runtime's references would bind to the program's definition";
    return false;
  }
  return true;
}

std::optional<PreparedFor> idr::driver::preparedFor(const llvm::Module &module) {
  auto *cpu = llvm::dyn_cast_or_null<llvm::MDString>(module.getModuleFlag(preparedCpuFlag));
  auto *features =
      llvm::dyn_cast_or_null<llvm::MDString>(module.getModuleFlag(preparedFeaturesFlag));
  if (!cpu || !features)
    return std::nullopt;
  return PreparedFor{cpu->getString(), features->getString()};
}

void idr::driver::retarget(llvm::Module &module, const llvm::TargetMachine &machine) {
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

bool idr::driver::linkRuntime(llvm::Module &program, const llvm::Target &target,
                              const llvm::Triple &triple, const llvm::TargetMachine &machine) {
  std::unique_ptr<llvm::Module> runtime =
      readRuntime(program.getContext(), program.getTargetTriple(), program.getDataLayout());
  if (!runtime || !namesApart(program, *runtime))
    return false;
  if (!nativeRuns(*runtime, target, triple, machine))
    for (llvm::GlobalValue &value : runtime->global_values())
      if (value.hasAvailableExternallyLinkage())
        value.setLinkage(llvm::GlobalValue::ExternalLinkage);
  if (llvm::Linker::linkModules(program, std::move(runtime), llvm::Linker::LinkOnlyNeeded)) {
    Report() << "internal error: linking the runtime into the program failed";
    return false;
  }
  return true;
}
