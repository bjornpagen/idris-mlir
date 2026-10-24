// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::end: the one place a process ends. Every ending is a type of its own,
// holding what its message says and no more, and `end` of it is the whole
// way out: what it writes first (the program's output and files, its
// output alone, or nothing), its message on standard error, `<program>:
// fatal: <what>`, and then its exit status or its signal, each from the
// table the specification prints (IdrisMLIR.Spec.Runtime.Endings). So a
// crash cannot be written without its site, an exit cannot carry a status
// no parent can read, and out of memory names no allocation.
#pragma once

#include "idris_rt.h"

// The ending table: the causes and their phrases, the internal errors and
// theirs, the fixed statuses, the signals, and the endings of each way out
// with what each writes first; printed from the specification.
#include "idr/IR/Generated/Endings.h.inc"

#include <stddef.h>
#include <stdint.h>

namespace rt::end {

// Each ending below names its case in the closed set of its way out (a
// status no program chooses, the status the program chose, or a signal),
// and holds what its message says. Which way it leaves by, its status or
// its signal, and what it writes first are that set's table, never stated
// here.

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
  static constexpr idr::endings::FixedEnding kind = idr::endings::FixedEnding::Returned;
};

// The program ended itself with a status a parent reads, a byte by type:
// the guard before an exit made it one, or crashed at the exit's site.
struct Exited {
  static constexpr idr::endings::ChosenEnding kind = idr::endings::ChosenEnding::Exited;
  uint8_t status;
};

// A crash of a cause of the closed set, at its site.
struct Failed {
  static constexpr idr::endings::FixedEnding kind = idr::endings::FixedEnding::Failed;
  idr::endings::CrashCause cause;
  Site site;
};

// A crash of the text a trusted library gave idris_crash, at its site.
struct Said {
  static constexpr idr::endings::FixedEnding kind = idr::endings::FixedEnding::Said;
  const idris_rt_str *message;
  Site site;
};

// The machine ran out of memory: the system refused memory (its address
// space, its commit limit) or the host's limit, which the runtime keeps to,
// was reached. No site: the language promises nothing of which allocation
// meets it.
struct OutOfMemory {
  static constexpr idr::endings::FixedEnding kind = idr::endings::FixedEnding::OutOfMemory;
};

// This machine cannot run the program: its processor lacks features the
// program was compiled to use (their IDRIS_RT_CPU_FEATURES bits), or its
// page is not the one the runtime was built for.
struct MissingFeatures {
  static constexpr idr::endings::FixedEnding kind = idr::endings::FixedEnding::MissingFeatures;
  uint64_t missing;
};
struct WrongPage {
  static constexpr idr::endings::FixedEnding kind = idr::endings::FixedEnding::WrongPage;
  size_t built;
  size_t system;
};

// A reader of one of the program's outputs went away: the write that met
// it failed, and the program ends by the signal Unix tools die of.
struct Piped {
  static constexpr idr::endings::SignalEnding kind = idr::endings::SignalEnding::Piped;
};

// Bugs of the compiler's or the runtime's, found as the program runs: the
// stack reaching a guard, which every frame was sized not to; in the checked
// runtime, cells live when main returns, a count operation on a cell that
// died, and a call that held more bytes it no longer needs than the bound
// the compiler computed for its function; the allocator's own fatal error; a
// library's hardening check.
struct StackExhausted {
  static constexpr idr::endings::SignalEnding kind = idr::endings::SignalEnding::StackExhausted;
};
struct CellsLeaked {
  static constexpr idr::endings::SignalEnding kind = idr::endings::SignalEnding::CellsLeaked;
  uint64_t cells;
};
struct CountOfDeadCell {
  static constexpr idr::endings::SignalEnding kind = idr::endings::SignalEnding::CountOfDeadCell;
};
struct FrameBoundExceeded {
  static constexpr idr::endings::SignalEnding kind =
      idr::endings::SignalEnding::FrameBoundExceeded;
  const idris_rt_text *function;
  uint64_t held;
  uint64_t bound;
};
struct AllocatorFailed {
  static constexpr idr::endings::SignalEnding kind = idr::endings::SignalEnding::AllocatorFailed;
  const char *text;
};
struct LibraryFailed {
  static constexpr idr::endings::SignalEnding kind = idr::endings::SignalEnding::LibraryFailed;
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
