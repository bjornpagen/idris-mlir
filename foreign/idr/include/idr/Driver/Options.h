// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir's command line, read once into what the invocation does: each
// action holds the options it reads, and an option of the driver's given
// to an action that does not read it is a usage error. The options are
// Options.cpp's alone, defined in one unit so that they register, and
// --help lists them, in the order they are written there. Also the exit
// statuses and the triple compiled for. IDRIS_MLIR_RUNTIME, the runtime the
// build prepared, IDRIS_MLIR_PINNED_CC, the clang that links programs,
// IDRIS_MLIR_IDRIS_PREFIX, the Idris prefix the frontend reads, and the
// target's triple and CPU are compile definitions of the driver.
#ifndef IDR_DRIVER_OPTIONS_H
#define IDR_DRIVER_OPTIONS_H

#include "idr/Driver/Artifacts.h"

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Error.h"

#include <string>
#include <variant>
#include <vector>

namespace idr::driver {

// Exit statuses, the frontend's too: an internal error or a contract
// violation is 1, a usage error 2, and any error of the program's 3: a
// refusal, which names its rule.
inline constexpr int ok = 0, failure = 1, usage = 2, rejected = 3;

// The runtime the build prepared (--prepare-runtime), which every
// executable links and every compilation reads unless --runtime names
// another.
inline constexpr llvm::StringLiteral preparedRuntime = IDRIS_MLIR_RUNTIME;

// Compile the plan's input into its product: with the runtime at
// `runtime`, what --prepare-runtime wrote or the archive it reads, whose
// bitcode joins the program and which an executable links; on a pool of
// `threads` threads, at least one, which the output bytes do not depend
// on; and with -log-actions-to logging only the actions of `tags`, every
// one when there are none.
struct Compile {
  Plan plan;
  std::string runtime;
  unsigned threads;
  std::vector<std::string> tags;
};

// Prepare the runtime archive at `archive` once, for every program, into
// the object at `output` (--prepare-runtime).
struct Prepare {
  std::string output;
  std::string archive;
};

// What the build decided, which a --print option asks and the answer
// prints: the runtime it prepared, the target triple, the arguments that
// link a program for the target, and the CPU code is compiled for.
enum class Question { Runtime, TargetTriple, LinkFlags, TargetCpu };
struct Print {
  Question question;
};

// What one invocation does.
using Invocation = std::variant<Compile, Prepare, Print>;

// The invocation the command line asks for, read once
// ParseCommandLineOptions has parsed it: an option outside its action, a
// compilation without an input or -o or whose outputs collide, the
// frontend's options for a module, and what MLIR's own options ask that
// the command line alone rules out are each a usage error, said in the
// Error, before anything runs or is written.
llvm::Expected<Invocation> readInvocation();

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
