// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idris-mlir's command line, read once into what the invocation does: each
// action holds the options it reads, and an option of the driver's given
// to an action that does not read it is a usage error. The options are
// Options.cpp's alone, defined in one unit so that they register, and
// --help lists them, in the order they are written there. Also a usage
// error's exit status and the triple compiled for. IDRIS_MLIR_RUNTIME, the
// runtime the build prepared, IDRIS_MLIR_PINNED_CC, the clang that links
// programs, IDRIS_MLIR_IDRIS_PREFIX, the Idris prefix the frontend reads,
// and the target's triple and CPU are compile definitions of the driver.
#ifndef IDR_DRIVER_OPTIONS_H
#define IDR_DRIVER_OPTIONS_H

#include "idr/Driver/Artifacts.h"
#include "idr/Transforms/Expect.h"

#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Error.h"

#include <cstdint>
#include <string>
#include <variant>
#include <vector>

namespace idr::driver {

// The status of a command line no invocation reads, before anything runs:
// any other ending is a compilation's verdict, whose status is its row's
// (exitStatus, Verdict.h), the frontend's too.
inline constexpr int usage = 2;

// The runtime the build prepared (--prepare-runtime), which every
// executable links and every compilation reads unless --runtime names
// another.
inline constexpr llvm::StringLiteral preparedRuntime = IDRIS_MLIR_RUNTIME;

// What is checked after each pass of the pipeline: the verifier, always,
// and with it the passes' contracts (--idr-contracts), which the tests ask
// for (idr/Transforms/Contracts.h).
enum class PassChecks : std::uint8_t { Verifier, Contracts };

// Compile the plan's input into its product: with the runtime at
// `runtime`, what --prepare-runtime wrote or the archive it reads, whose
// bitcode joins the program and which an executable links; on a pool of
// `threads` threads, at least one, which the output bytes do not depend
// on; with -log-actions-to logging only the actions of `tags`, every one
// when there are none; checking `checks` after every pass, and the
// properties a test states of the stages (--idr-expect-at), each where the
// program is at its stage.
struct Compile {
  Plan plan;
  std::string runtime;
  unsigned threads;
  std::vector<std::string> tags;
  PassChecks checks;
  llvm::SmallVector<idr::expect::StageRequest> stages;
};

// Prepare the runtime archive at `archive` once, for every program, into
// the object at `output` (--prepare-runtime).
struct Prepare {
  std::string output;
  std::string archive;
};

// What the build decided, which a --print option asks and the answer
// prints: the runtime it prepared, the target triple, the arguments that
// link a program for the target, and the flags of the CPU code is compiled
// for.
enum class Question { Runtime, TargetTriple, LinkFlags, CpuFlags };
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

// The pinned clang, which links every program for the target (its
// configuration file gives the target's C library, the runtimes, lld and
// the kind of executable).
inline constexpr llvm::StringLiteral pinnedCc = IDRIS_MLIR_PINNED_CC;

} // namespace idr::driver

#endif // IDR_DRIVER_OPTIONS_H
