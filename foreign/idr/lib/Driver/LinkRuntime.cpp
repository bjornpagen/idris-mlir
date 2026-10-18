// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's bitcode linked into the program's module, and its functions
// raised to the program's CPU.

#include "idr/Driver/Runtime.h"
#include "idr/IR/IdrDialect.h"

// The target entry's list of processor features, an X-macro.
#include "cpu_features.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/Mangler.h"
#include "llvm/IR/Module.h"
#include "llvm/Linker/Linker.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Triple.h"

#include <memory>
#include <string>
#include <utility>
#include <variant>

using namespace idr::driver;

// Whether the prepared runtime's native half runs wherever the program does:
// the program's CPU has every feature of the CPU that half was compiled for
// that the processor test at the program's entry can name
// (IDRIS_RT_CPU_FEATURES), so the test covers both. The build prepares the
// runtime for the CPU every program is compiled for, so this fails only for
// a runtime prepared elsewhere for a larger one, whose bodies the program
// then compiles itself.
static bool nativeRuns(const PreparedFor &prepared, const llvm::Target &target,
                       const llvm::Triple &triple, const llvm::TargetMachine &machine) {
  std::unique_ptr<llvm::MCSubtargetInfo> native(
      target.createMCSubtargetInfo(triple, prepared.cpu, prepared.features));
  const llvm::MCSubtargetInfo &program = machine.getMCSubtargetInfo();
#define IDR_FEATURE(bit, test, name)                                                             \
  if (native->checkFeatures("+" name) && !program.checkFeatures("+" name))                       \
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
// refused at `source` before anything is linked.
static mlir::LogicalResult namesApart(const llvm::Module &program, const llvm::Module &runtime,
                                      mlir::ModuleOp source) {
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
    return idr::refuse(source, idr::Rule::ProgramShape)
           << "the program defines " << value.getName() << ", which the runtime "
           << (named->second->isDeclaration() ? "refers to" : "defines")
           << " too: the runtime's references would bind to the program's definition";
  }
  return mlir::success();
}

void idr::driver::retarget(llvm::Module &runtime, const llvm::TargetMachine &machine) {
  std::string cpuFeatures = machine.getTargetFeatureString().str();
  for (llvm::Function &function : runtime) {
    // A declaration has no code to compile for a CPU, and a baseline
    // function keeps the baseline.
    if (function.isDeclaration() || function.hasFnAttribute(baselineMark))
      continue;
    std::string features = function.getFnAttribute(featuresMark).getValueAsString().str();
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

mlir::LogicalResult idr::driver::linkRuntime(llvm::Module &program, mlir::ModuleOp source,
                                             llvm::StringRef path, const llvm::Target &target,
                                             const llvm::Triple &triple,
                                             const llvm::TargetMachine &machine) {
  mlir::FailureOr<std::variant<Archived, Prepared>> read =
      readRuntime(path, program.getContext(), program.getTargetTriple(), program.getDataLayout(),
                  *source.getContext());
  if (mlir::failed(read))
    return mlir::failure();
  // The archive's bodies are definitions; a prepared runtime's join as
  // available_externally only where its native half runs on the program's
  // CPU.
  std::unique_ptr<llvm::Module> runtime = std::visit(
      llvm::makeVisitor([](Archived &archived) { return std::move(archived.module); },
                        [&](Prepared &prepared) {
                          if (!nativeRuns(prepared.target, target, triple, machine))
                            for (llvm::GlobalValue &value : prepared.module->global_values())
                              if (value.hasAvailableExternallyLinkage())
                                value.setLinkage(llvm::GlobalValue::ExternalLinkage);
                          return std::move(prepared.module);
                        }),
      *read);
  if (mlir::failed(namesApart(program, *runtime, source)))
    return mlir::failure();
  retarget(*runtime, machine);
  if (llvm::Linker::linkModules(program, std::move(runtime), llvm::Linker::LinkOnlyNeeded))
    return mlir::emitError(mlir::UnknownLoc::get(source.getContext()))
           << "linking the runtime into the program failed";
  // The marks are the runtime's, read by retarget alone: once the runtime
  // has joined, they go.
  for (llvm::Function &function : program) {
    function.removeFnAttr(cpuMark);
    function.removeFnAttr(featuresMark);
  }
  return mlir::success();
}
