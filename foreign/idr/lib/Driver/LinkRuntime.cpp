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
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/Twine.h"
#include "llvm/IR/Attributes.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/InstrTypes.h"
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
  // A body the program joins becomes program code, whose frames code
  // generation sizes and the build checks against the guard: it takes no
  // stack probe, and it would give one to every program function it
  // inlines into. The runtime's native half keeps its own.
  llvm::StringSet<> runtimeFunctions;
  for (llvm::Function &function : *runtime) {
    function.removeFnAttr("probe-stack");
    function.removeFnAttr("stack-probe-size");
    if (!function.isDeclaration())
      runtimeFunctions.insert(function.getName());
  }
  if (llvm::Linker::linkModules(program, std::move(runtime), llvm::Linker::LinkOnlyNeeded))
    return mlir::emitError(at) << "linking the runtime into the program failed";
  // A program function past the budget calls the runtime
  // (idr::target::inlineCallerInstructions), all but the bodies the runtime
  // marks always inline, whose call would cost more than they do: among
  // them the frame-bound account's entries, empty in the shipped runtime,
  // which no shipped program may name. A call's own noinline outranks its
  // callee's alwaysinline, so such a call is never marked.
  for (llvm::Function &function : program) {
    if (function.isDeclaration() || runtimeFunctions.contains(function.getName()) ||
        function.getInstructionCount() <= idr::target::inlineCallerInstructions)
      continue;
    for (llvm::Instruction &instruction : llvm::instructions(function))
      if (auto *call = llvm::dyn_cast<llvm::CallBase>(&instruction))
        if (const llvm::Function *callee = call->getCalledFunction();
            callee && runtimeFunctions.contains(callee->getName()) &&
            !callee->hasFnAttribute(llvm::Attribute::AlwaysInline))
          call->setIsNoInline();
  }
  return mlir::success();
}
