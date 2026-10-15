// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir's command line, its exit statuses and the triple it compiles
// for. Every option is defined in one unit (Options.cpp), so that they
// register, and --help lists them, in the order they are written there.
// IDRIS_MLIR_RUNTIME and IDRIS_MLIR_RUNTIME_BITCODE_SECTION, the runtime the
// build prepared and where it keeps its bitcode, IDRIS_MLIR_PINNED_CC, the
// clang that links programs, IDRIS_MLIR_IDRIS_PREFIX, the Idris prefix the
// frontend reads, and the target's triple and CPU are compile definitions
// of the driver.
#ifndef IDR_DRIVER_OPTIONS_H
#define IDR_DRIVER_OPTIONS_H

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/CommandLine.h"

#include <string>

namespace idr::driver {

extern llvm::cl::opt<std::string> inputPath;
extern llvm::cl::opt<std::string> outputPath;
extern llvm::cl::opt<bool> objectOnly;
extern llvm::cl::list<std::string> packages;
extern llvm::cl::list<std::string> packagePath;
extern llvm::cl::opt<std::string> idrisPrefix;
extern llvm::cl::opt<bool> noPrelude;
extern llvm::cl::list<std::string> logActionsTags;
extern llvm::cl::opt<std::string> runtimePath;
extern llvm::cl::opt<std::string> runtimeBitcodeSection;
extern llvm::cl::opt<bool> printRuntime;
extern llvm::cl::opt<bool> prepareRuntime;
extern llvm::cl::opt<bool> printTargetTriple;
extern llvm::cl::opt<bool> printLinkFlags;
extern llvm::cl::opt<bool> printTargetCpu;
extern llvm::cl::opt<unsigned> numThreads;

// The threads a compilation may use: --num-threads when given, else
// every CPU. The default is maximal; a caller that wants headroom (our
// build and test scripts do, through IDRIS_MLIR_NCPU) says so with the
// flag. Output bytes do not depend on it.
unsigned threadBudget();

// Exit statuses, the frontend's too: an internal error or a contract
// violation is 1, a usage error 2, and any error of the program's 3: a
// refusal, which names its rule, on either side, or any error Idris
// reports.
inline constexpr int ok = 0, failure = 1, usage = 2, rejected = 3;

// Code is compiled for the triple the runtime is built for (the target
// entry's), which its bitcode carries, and for the entry's CPU, which every
// machine of the target since that CPU has; an executable names what an
// older one lacks (idris_rt_start). The module records both as its
// #llvm.target (idr-target); every link of a program is for the triple too
// (the --target of --print-link-flags).
inline constexpr llvm::StringLiteral targetTriple = IDRIS_MLIR_TARGET_TRIPLE;
inline constexpr llvm::StringLiteral targetCpu = IDRIS_MLIR_TARGET_CPU;

// The pinned clang, which links every program for the target (its
// configuration file gives the target's C library, the runtimes, lld and
// the kind of executable).
inline constexpr llvm::StringLiteral pinnedCc = IDRIS_MLIR_PINNED_CC;

} // namespace idr::driver

#endif // IDR_DRIVER_OPTIONS_H
