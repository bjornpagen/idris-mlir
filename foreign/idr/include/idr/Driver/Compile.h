// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One compilation, the whole chain: the frontend for Idris source, the
// pipeline and LLVM in process, and the link by the pinned clang, each
// timed under one root, so that -mlir-timing reports the whole command.
// Every step that fails says why in the compilation's diagnostic engine,
// which folds each diagnostic into the verdict and prints it.
#ifndef IDR_DRIVER_COMPILE_H
#define IDR_DRIVER_COMPILE_H

#include "idr/Driver/Artifacts.h"
#include "idr/Driver/Options.h"
// The target entry's link flags, an X-macro.
#include "idr/TargetEntry.h"

#include "mlir/IR/Diagnostics.h"
#include "mlir/Support/LLVM.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/SourceMgr.h"

#include <memory>
#include <string>

namespace mlir {
class DialectRegistry;
class MLIRContext;
class PassInstrumentation;
class TimingScope;
} // namespace mlir

namespace llvm {
class Target;
class ThreadPoolInterface;
class Triple;
} // namespace llvm

namespace idr::driver {

class Outcome;

// What links a program for the target entry, after its objects, the
// runtime and -o: --target with the triple, then the entry's executable and
// program link flags and GMP. The link and --print-link-flags read this one
// list.
inline constexpr llvm::StringLiteral linkFlags[] = {
#define IDR_LINK_FLAG(flag) flag,
    IDRIS_MLIR_LINK_FLAGS(IDR_LINK_FLAG)
#undef IDR_LINK_FLAG
};

// idris-mlir-front beside this executable, by its real path: the build
// links the frontend there, and a copy of idris-mlir alone runs no other
// frontend, nor one found on PATH.
std::string frontendBeside(const char *argv0);

// The dialects a handoff module is written in, as the frontend writes one,
// with their flow models: what a module that holds an idr.program may hold
// (run asks), and the first part of what registerCompiler registers.
void registerHandoff(mlir::DialectRegistry &registry);

// The dialects, interfaces and translations a compilation's context needs,
// and nothing else: the dialects a handoff module is written in with their
// flow models; the LLVM dialect and DLTI, the pipeline's output's; every
// dialect a pass of the pipeline loads, with the models of them its passes
// read; the ConvertToLLVMPatternInterface of each dialect convert-to-llvm
// meets; the transform ops the schedule library is written in; and the
// translations of the LLVM dialect and of builtin to LLVM IR. Every pass
// the pipeline runs is registered by registerCompilerPasses, before the
// options that name passes (-mlir-print-ir-after and the like) are. The
// tools, which read any module, register upstream's all.
void registerCompiler(mlir::DialectRegistry &registry);
void registerCompilerPasses();

// The chain, from the plan's input to its artifacts, which are kept only
// when the verdict is accepted, and to the report, written whatever the
// verdict; the exit status of the verdict.
int compile(llvm::StringRef frontendPath, Compile invocation);

// The module the artifacts name into the objects of its bins, written where
// the artifacts say, on `context`, whose diagnostics fold into `outcome`:
// the refusals a module written by the frontend holds, re-emitted; a
// handoff module through the pipeline and LLVM; a module of the LLVM
// dialect alone, the pipeline's output, through LLVM. `made` is the status
// the frontend finished with, or ok for a module given as the input: a
// frontend that failed must have written a refusal. The parse adds the
// module's file to `sources`. Each pass and stage is timed under
// `rootTiming`, and every pass statistic is folded into `outcome`. Failure
// once a step has said why.
mlir::LogicalResult run(int made, const Compile &invocation, Artifacts &artifacts,
                        mlir::MLIRContext &context, llvm::SourceMgr &sources,
                        llvm::ThreadPoolInterface &pool, mlir::TimingScope &rootTiming,
                        Outcome &outcome);

// Every diagnostic of `context`, from whichever thread delivers it, into
// `outcome`: the verdict it makes and its fields in the report. The handler
// then passes it on, to the ones registered before it that print it.
void foldDiagnostics(mlir::MLIRContext &context, Outcome &outcome);

// A compilation's diagnostics, folded and printed, from its context's
// making until just before the context goes: every diagnostic folds into
// `outcome` (foldDiagnostics), then one located in a file goes to MLIR's
// SourceMgrDiagnosticHandler, which shows its line, and any other error is
// printed in the driver's own form (Report.h's), `idris-mlir: <message>`,
// with `internal error: ` before a message that names no rule. The class
// printed and the verdict folded are one predicate's. The driver's own
// refusals carry the dialect's rule (idr::refuse), so the context holds the
// idr dialect from here on.
class Diagnostics {
public:
  Diagnostics(mlir::MLIRContext &context, Outcome &outcome);

  // Where the parse adds the file it reads, so its lines can be shown.
  llvm::SourceMgr &sources() { return sourceMgr; }

private:
  llvm::SourceMgr sourceMgr;
  mlir::SourceMgrDiagnosticHandler located;
  mlir::ScopedDiagnosticHandler unlocated;
};

// The instrumentation that adds each statistic's increase over every run
// of every pass into `outcome`.
std::unique_ptr<mlir::PassInstrumentation> foldStatistics(Outcome &outcome);

// LLVM's target for the triple, with its code generator and assembly
// parser (the runtime carries inline assembly) initialized; an error in
// `context` when LLVM has none.
mlir::FailureOr<const llvm::Target *> nativeTarget(const llvm::Triple &triple,
                                                   mlir::MLIRContext &context);

} // namespace idr::driver

#endif // IDR_DRIVER_COMPILE_H
