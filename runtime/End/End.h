// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::end: the one place a process ends. Every ending is a type of its own,
// holding what its message says and no more, and `end` of it is the whole
// way out: standard output's pending bytes written, the program's files
// written and closed (every ending but an internal error, which may be met
// in a signal handler), its message on standard error, `<program>: fatal:
// <what>`, and then its exit status or its signal, each from the table the
// specification prints (IdrisMLIR.Spec.Runtime.Endings). So a crash cannot
// be written without its site, an exit cannot carry a status no parent can
// read, and out of memory names no allocation.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "idris_rt.h"

// The ending table: the causes and their phrases, the internal errors and
// theirs, the fixed statuses, the signals; printed from the specification.
#include "idr/IR/Generated/Endings.h.inc"

#include <stddef.h>
#include <stdint.h>

namespace rt::end {

// What an ending writes before it says anything: everything the program
// wrote, standard output's pending bytes and its files, closed; or standard
// output's pending bytes alone, with write(2), for an internal error, which
// may be met in a signal handler, where no stream of the C library may be
// touched; or nothing, for a machine that cannot run the program, which
// has written nothing and runs only code compiled for the target's baseline.
enum class Cleans : uint8_t { Everything, OutputOnly, Nothing };

// Where a crash is: the function its site lies in, its source file, its
// line and its column, each file and function one static text of the
// program, shared by every site that names it.
struct Site {
  const idris_rt_text *function;
  const idris_rt_text *file;
  uint32_t line;
  uint32_t column;
};

// The program's main returned.
struct Returned {
  static constexpr Cleans cleans = Cleans::Everything;
};

// The program ended itself with a status a parent reads, a byte by type:
// the guard before an exit made it one, or crashed at the exit's site.
struct Exited {
  static constexpr Cleans cleans = Cleans::Everything;
  uint8_t status;
};

// A crash of a cause of the closed set, at its site.
struct Failed {
  static constexpr Cleans cleans = Cleans::Everything;
  idr::endings::CrashCause cause;
  Site site;
};

// A crash of the text a trusted library gave idris_crash, at its site.
struct Said {
  static constexpr Cleans cleans = Cleans::Everything;
  const idris_rt_str *message;
  Site site;
};

// A crash at an exit whose status no parent could read, outside 0 to 255.
struct Unreportable {
  static constexpr Cleans cleans = Cleans::Everything;
  int64_t status;
  Site site;
};

// The machine ran out of memory: the system refused memory (its address
// space, its commit limit) or the host's limit, which the runtime keeps to,
// was reached. No site: the language promises nothing of which allocation
// meets it.
struct OutOfMemory {
  static constexpr Cleans cleans = Cleans::Everything;
};

// This machine cannot run the program: its processor lacks features the
// program was compiled to use (their IDRIS_RT_CPU_FEATURES bits), or its
// page is not the one the runtime was built for.
struct MissingFeatures {
  static constexpr Cleans cleans = Cleans::Nothing;
  uint64_t missing;
};
struct WrongPage {
  static constexpr Cleans cleans = Cleans::Nothing;
  size_t built;
  size_t system;
};

// A reader of one of the program's outputs went away: the write that met
// it failed, and the program ends by the signal Unix tools die of.
struct Piped {
  static constexpr Cleans cleans = Cleans::Everything;
  static constexpr idr::endings::EndingSignal signal = idr::endings::EndingSignal::BrokenPipe;
};

// Bugs of the compiler's or the runtime's, found as the program runs: the
// stack reaching a guard, which every frame was sized not to; in the checked
// runtime, cells live when main returns, a count operation on a cell that
// died, and a call that held more bytes it no longer needs than the bound
// the compiler computed for its function; the allocator's own fatal error; a
// library's hardening check.
struct StackExhausted {
  static constexpr Cleans cleans = Cleans::OutputOnly;
  static constexpr idr::endings::EndingSignal signal = idr::endings::EndingSignal::Abort;
};
struct CellsLeaked {
  static constexpr Cleans cleans = Cleans::OutputOnly;
  static constexpr idr::endings::EndingSignal signal = idr::endings::EndingSignal::Abort;
  uint64_t cells;
};
struct CountOfDeadCell {
  static constexpr Cleans cleans = Cleans::OutputOnly;
  static constexpr idr::endings::EndingSignal signal = idr::endings::EndingSignal::Abort;
};
struct FrameBoundExceeded {
  static constexpr Cleans cleans = Cleans::OutputOnly;
  static constexpr idr::endings::EndingSignal signal = idr::endings::EndingSignal::Abort;
  const idris_rt_text *function;
  uint64_t held;
  uint64_t bound;
};
struct AllocatorFailed {
  static constexpr Cleans cleans = Cleans::OutputOnly;
  static constexpr idr::endings::EndingSignal signal = idr::endings::EndingSignal::Abort;
  const char *text;
};
struct LibraryFailed {
  static constexpr Cleans cleans = Cleans::OutputOnly;
  static constexpr idr::endings::EndingSignal signal = idr::endings::EndingSignal::Abort;
  const char *text;
};

// Ends the process as `ending` says. Async-signal-safe for an internal
// error, which the fault handler meets: it then writes with write(2) alone
// and touches no stream of the C library. Compiled for the target's
// baseline, since a machine that cannot run the program ends through it
// before anything shows the processor has more.
template <class E>
[[noreturn]] void end(const E &ending) noexcept;

// The name every message begins with: the program's, as the driver built
// it, or the tool's that runs on the runtime. Set once, first, by whichever
// starts the runtime (idris_rt_start, idris_rt_run_on_stack).
void name(const char *bytes, size_t length) noexcept;

} // namespace rt::end
