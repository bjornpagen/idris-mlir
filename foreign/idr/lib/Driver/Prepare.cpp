// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The prepared runtime: one optimized module, written as native code with
// its bitcode beside it, which records what code generation gave the
// native code's frames.

#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Compile.h"
#include "idr/Driver/Options.h"
#include "idr/Driver/Runtime.h"
#include "idr/Driver/StackBound.h"
#include "idr/Driver/Verdict.h"
#include "idr/Support/Match.h"
#include "idr/Target/Target.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"

#include "llvm/Bitcode/BitcodeWriter.h"
#include "llvm/IR/GlobalObject.h"
#include "llvm/IR/GlobalValue.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Metadata.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Casting.h"
#include "llvm/Support/FileSystem.h"
#include "llvm/Support/ToolOutputFile.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Target/TargetMachine.h"
#include "llvm/TargetParser/Triple.h"
#include "llvm/Transforms/IPO/Internalize.h"
#include "llvm/Transforms/Utils/Cloning.h"

#include <memory>
#include <string>
#include <system_error>
#include <utility>
#include <variant>

using namespace idr::driver;

// The optimized runtime's symbols, so that a program's object can name each
// one: a body it did not inline, a global an inlined body reads. Every
// local one becomes external with hidden visibility; the names are unique,
// since readRuntime's linker named the members' local symbols apart.
static mlir::LogicalResult externalize(llvm::Module &runtime, mlir::Location at) {
  for (llvm::GlobalValue &value : runtime.global_values()) {
    if (value.isDeclaration())
      continue;
    if (!llvm::isa<llvm::GlobalObject>(value) || !value.hasName())
      return mlir::emitError(at) << "the optimization left the runtime "
                                 << (value.hasName() ? "alias " : "an unnamed global ")
                                 << value.getName() << ", which the native half cannot name";
    if (value.hasLocalLinkage()) {
      value.setLinkage(llvm::GlobalValue::ExternalLinkage);
      value.setVisibility(llvm::GlobalValue::HiddenVisibility);
    }
    value.setDSOLocal(true);
  }
  return mlir::success();
}

// The archive's runtime, read for the program's CPU, optimized and written
// as the object at `output` with its bitcode in the file beside it, which
// records what it is and what its native half's frames are.
static mlir::LogicalResult prepareArchive(Archived &archived, llvm::TargetMachine &machine,
                                          llvm::StringRef output, mlir::MLIRContext &context) {
  mlir::Location at = mlir::UnknownLoc::get(&context);
  llvm::Module &runtime = *archived.module;
  llvm::LLVMContext &llvmContext = runtime.getContext();
  // Programs reach the C ABI and nothing else.
  llvm::internalizeModule(runtime, [](const llvm::GlobalValue &value) {
    return value.getName().starts_with("idris_rt_");
  });
  idr::target::optimize(runtime, machine);
  if (mlir::failed(externalize(runtime, at)))
    return mlir::failure();
  for (auto [flag, value] : {std::pair{preparedArchiveFlag, &archived.identity.archive},
                             std::pair{preparedCpuFlag, &archived.identity.cpu},
                             std::pair{preparedFeaturesFlag, &archived.identity.features}})
    runtime.addModuleFlag(llvm::Module::Error, flag, llvm::MDString::get(llvmContext, *value));
  // Its calls, read once before code generation, which rewrites the module
  // it compiles: a call on a cycle that is no tail call, or a frame sized at
  // run time, leaves the runtime's stack with no bound.
  mlir::FailureOr<stack::Graph> calls = stack::Graph::of(runtime, context);
  if (mlir::failed(calls))
    return mlir::failure();
  // Kept only once the object is written too.
  std::error_code error;
  std::string path = besideObject(output);
  llvm::ToolOutputFile beside(path, error, llvm::sys::fs::OF_None);
  if (error)
    return cannotWrite(context, path, error);
  // The native half, from a copy of the module, each frame code generation
  // lays out gathered.
  stack::Frames frames;
  {
    std::unique_ptr<llvm::Module> native = llvm::CloneModule(runtime);
    stack::ask(*native);
    std::unique_ptr<llvm::DiagnosticHandler> previous = llvmContext.getDiagnosticHandler();
    llvmContext.setDiagnosticHandler(stack::gather(frames));
    mlir::LogicalResult emitted = emit(*native, machine, output, context);
    llvmContext.setDiagnosticHandler(std::move(previous));
    if (mlir::failed(emitted))
      return mlir::failure();
  }
  calls->record(runtime, frames, machine);
  // The bitcode half: the same module, every definition
  // available_externally.
  for (llvm::GlobalValue &value : runtime.global_values())
    if (!value.isDeclaration())
      value.setLinkage(llvm::GlobalValue::AvailableExternallyLinkage);
  llvm::WriteBitcodeToFile(runtime, beside.os());
  beside.keep();
  return mlir::success();
}

// The steps of --prepare-runtime, until one fails, which has said why.
static mlir::LogicalResult prepareRuntime(const Prepare &invocation, mlir::MLIRContext &context) {
  mlir::Location at = mlir::UnknownLoc::get(&context);
  if (mlir::failed(makeDirectoryOf(invocation.output, context)))
    return mlir::failure();
  mlir::FailureOr<const llvm::Target *> target =
      nativeTarget(llvm::Triple(idr::target::triple), context);
  if (mlir::failed(target))
    return mlir::failure();
  llvm::Expected<std::unique_ptr<llvm::TargetMachine>> made = idr::target::machine(**target);
  if (!made)
    return mlir::emitError(at) << llvm::toString(made.takeError());
  llvm::TargetMachine &machine = **made;
  llvm::LLVMContext llvmContext;
  mlir::FailureOr<std::variant<Archived, Prepared>> runtime =
      readRuntime(invocation.archive, llvmContext, machine, context);
  if (mlir::failed(runtime))
    return mlir::failure();
  // Only the archive is prepared.
  return idr::match(
      *runtime,
      [&](Archived &archived) {
        return prepareArchive(archived, machine, invocation.output, context);
      },
      [&](const Prepared &) -> mlir::LogicalResult {
        return mlir::emitError(at) << "runtime " << invocation.archive
                                   << " is prepared already; --prepare-runtime reads the archive";
      });
}

int idr::driver::prepare(const Prepare &invocation) {
  // Declared before the context, whose diagnostics fold into it until it
  // goes. The context holds no IR: it is the diagnostic engine, which folds
  // the verdict and prints, as a compilation's does.
  Outcome outcome;
  mlir::MLIRContext context(mlir::MLIRContext::Threading::DISABLED);
  Diagnostics diagnostics(context, outcome);
  // A step that failed has said why: the verdict is the outcome.
  (void)prepareRuntime(invocation, context);
  return statusOf(outcome.verdict());
}
