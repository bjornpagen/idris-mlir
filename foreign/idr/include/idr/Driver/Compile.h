// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One compilation, the whole chain: the frontend for Idris source, the
// pipeline and LLVM in process, and the link by the pinned clang, each
// timed under one root, so that -mlir-timing reports the whole command.
#ifndef IDR_DRIVER_COMPILE_H
#define IDR_DRIVER_COMPILE_H

#include "idr/Driver/Artifacts.h"
// The target entry's link flags, an X-macro.
#include "idr/TargetEntry.h"

#include "llvm/ADT/StringRef.h"

#include <memory>
#include <string>

namespace mlir {
class MLIRContext;
class PassInstrumentation;
class TimingScope;
} // namespace mlir

namespace llvm {
class Target;
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

// The chain, from the input to the artifacts, which are kept only once
// every step succeeded, and to the report, written whatever the verdict;
// the exit status of the verdict, or of a usage error.
int compile(llvm::StringRef frontendPath, Artifacts &artifacts);

// The module the artifacts name into the objects of its bins, written where
// the artifacts say: a handoff module through the pipeline and LLVM, a
// module of the LLVM dialect alone, the pipeline's output, through LLVM.
// Each pass and stage is timed under `rootTiming`, and every diagnostic and
// pass statistic is folded into `outcome`. Zero, the status of the verdict
// a step stopped on, or a status of a step that failed with none reported
// (a usage error among them).
int run(Artifacts &artifacts, mlir::TimingScope &rootTiming, Outcome &outcome);

// Every diagnostic of `context`, from whichever thread delivers it, into
// `outcome`: the verdict it makes and its fields in the report. The handler
// then passes it on, to the one registered before it that prints it.
void foldDiagnostics(mlir::MLIRContext &context, Outcome &outcome);

// The instrumentation that adds each statistic's increase over every run
// of every pass into `outcome`.
std::unique_ptr<mlir::PassInstrumentation> foldStatistics(Outcome &outcome);

// LLVM's target for the triple, with its code generator and assembly
// parser (the runtime carries inline assembly) initialized; null, reported,
// when LLVM has none.
const llvm::Target *nativeTarget(const llvm::Triple &triple);

} // namespace idr::driver

#endif // IDR_DRIVER_COMPILE_H
