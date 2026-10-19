// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's bitcode linked into the program's module: the runtime
// idris-mlir is built with, and no other.

#include "idr/Driver/Runtime.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Target/Target.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/Mangler.h"
#include "llvm/IR/Module.h"
#include "llvm/Linker/Linker.h"

#include <memory>
#include <string>
#include <utility>
#include <variant>

using namespace idr::driver;

// The runtime read from `path` is one idris-mlir is built with: read from
// an archive the build made, for the program's CPU. Another archive, or a
// runtime prepared from one or for another CPU, would make a program's
// runtime code other than what the compiler is: it is refused, by what
// differs.
static mlir::LogicalResult isBuilt(const Identity &read, llvm::StringRef path,
                                   mlir::Location at) {
  llvm::SmallVector<std::string, 3> differs;
  llvm::ArrayRef<BuiltArchive> archives = builtArchives();
  auto named = [](const BuiltArchive &archive) {
    return (llvm::Twine(archive.digest) + " (" + archive.name + ")").str();
  };
  if (llvm::none_of(archives,
                    [&](const BuiltArchive &archive) { return archive.digest == read.archive; }))
    differs.push_back("its archive's digest is " + read.archive + ", and the build's archives' " +
                      llvm::join(llvm::map_range(archives, named), ", "));
  const idr::target::Cpu &program = idr::target::programCpu;
  if (read.cpu != program.name)
    differs.push_back("its CPU is " + read.cpu + ", and the program's " + program.name.str());
  if (read.features != program.features)
    differs.push_back("its features are " + read.features + ", and the program's " +
                      program.features.str());
  if (differs.empty())
    return mlir::success();
  mlir::InFlightDiagnostic refusal = idr::refuse(at, idr::Rule::Runtime);
  refusal << "runtime " << path << " is not the runtime idris-mlir is built with: "
          << llvm::join(differs, "; ");
  return refusal;
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

mlir::LogicalResult idr::driver::linkRuntime(llvm::Module &program, mlir::ModuleOp source,
                                             llvm::StringRef path,
                                             const llvm::TargetMachine &machine) {
  mlir::Location at = mlir::UnknownLoc::get(source.getContext());
  mlir::FailureOr<std::variant<Archived, Prepared>> read =
      readRuntime(path, program.getContext(), machine, *source.getContext());
  if (mlir::failed(read))
    return mlir::failure();
  if (mlir::failed(
          isBuilt(std::visit([](const auto &kind) { return kind.identity; }, *read), path, at)))
    return mlir::failure();
  std::unique_ptr<llvm::Module> runtime =
      std::visit([](auto &kind) { return std::move(kind.module); }, *read);
  if (mlir::failed(namesApart(program, *runtime, source)))
    return mlir::failure();
  if (llvm::Linker::linkModules(program, std::move(runtime), llvm::Linker::LinkOnlyNeeded))
    return mlir::emitError(at) << "linking the runtime into the program failed";
  return mlir::success();
}
