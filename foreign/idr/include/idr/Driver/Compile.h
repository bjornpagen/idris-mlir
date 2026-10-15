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

#include <string>

namespace mlir {
class TimingScope;
} // namespace mlir

namespace llvm {
class Target;
class Triple;
} // namespace llvm

namespace idr::driver {

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
// every step succeeded; an exit status.
int compile(llvm::StringRef frontendPath, Input kind, Artifacts &artifacts);

// The module the artifacts name through the pipeline and LLVM into the
// objects of its bins, written where the artifacts say, each pass and
// stage timed under `rootTiming`. An exit status.
int run(Artifacts &artifacts, mlir::TimingScope &rootTiming);

// LLVM's target for the triple, with its code generator and assembly
// parser (the runtime carries inline assembly) initialized; null, reported,
// when LLVM has none.
const llvm::Target *nativeTarget(const llvm::Triple &triple);

} // namespace idr::driver

#endif // IDR_DRIVER_COMPILE_H
