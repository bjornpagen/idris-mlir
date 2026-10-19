// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The program's entry, idris_rt_start: the processor test, the program's
// arguments, its stack, and its exit status. rt::io reads the program's
// arguments from here, so rt::start does not use rt::io.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"
#include "Start/Start.h"
#include "Strings/Strings.h"
#include "cpu_features.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace {

// The arguments main received, which idris_rt_start keeps before the
// program runs.
int argumentTotal = 0;
char **argumentText = nullptr;

struct Program {
  int64_t (*body)(void);
  int64_t status;
};

void runProgram(void *argument) {
  auto &program = *static_cast<Program *>(argument);
  program.status = program.body();
}

// The processor test runs before anything that may use the features it
// tests, so it stays compiled for the target's baseline: it is inlined into
// idris_rt_start, and what it calls is marked as idris_rt_start is.
// Names what the processor lacks, each feature by its name and each bit no
// feature names by its number, and ends the process as a crash does, before
// the program has written anything.
[[gnu::always_inline]] inline void checkCpu(uint64_t required) {
  uint64_t missing = required & ~rt::platform::cpuFeatures();
  if (missing == 0)
    return;
  static constexpr char lacks[] = "this processor lacks";
  static constexpr char bitText[] = " bit ";
  static constexpr char suffix[] = ", which the program was compiled to use";
  // The cause's pieces: its first and its last, and between them one for
  // each feature missing and two for each bit no feature names, at most two
  // for each of the requirement's 64 bits.
  rt::platform::Piece cause[2 + 2 * 64];
  char digits[64][rt::strings::intTextMax];
  size_t pieces = 0;
  cause[pieces++] = {lacks, sizeof lacks - 1};
#define IDRIS_RT_CPU_NAME(bit, test, name)                                                       \
  if ((missing >> (bit) & 1) != 0)                                                               \
    cause[pieces++] = {" " name, sizeof(name)};
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_NAME)
#undef IDRIS_RT_CPU_NAME
  // The requirement is the program's word, which may hold a bit the
  // target's list does not name (a program built against another list):
  // the processor lacks it all the same, so it is named by its number.
#define IDRIS_RT_CPU_BIT(bit, test, name) | uint64_t{1} << (bit)
  constexpr uint64_t named = 0 IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_BIT);
#undef IDRIS_RT_CPU_BIT
  for (uint64_t unnamed = missing & ~named; unnamed != 0; unnamed &= unnamed - 1) {
    auto bit = static_cast<unsigned>(__builtin_ctzll(unnamed));
    char *end = digits[bit] + sizeof digits[bit];
    char *start = rt::strings::formatUnsigned(bit, end);
    cause[pieces++] = {bitText, sizeof bitText - 1};
    cause[pieces++] = {start, static_cast<size_t>(end - start)};
  }
  cause[pieces++] = {suffix, sizeof suffix - 1};
  rt::platform::writeCrash(cause, pieces);
  rt::platform::exitProcess(IDRIS_RT_CRASHED);
}

// What the program's runner does when its stack runs out: a crash, from the
// fault handler, where its flush, write and exit are safe.
[[noreturn]] void programExhausted() {
  static constexpr char cause[] = "stack exhausted";
  idris_rt_crash(cause, sizeof cause - 1);
}

} // namespace

namespace rt::start {

void checkStatus(int64_t status, Ending ending) {
  if (status >= 0 && status <= 255)
    return;
  static constexpr char mainReturned[] = "main returned ";
  static constexpr char exited[] = "exit with ";
  static_assert(sizeof exited <= sizeof mainReturned, "the cause has room for either");
  static constexpr char suffix[] = ", which is not an exit status (0 to 255)";
  char cause[sizeof mainReturned - 1 + rt::strings::intTextMax + sizeof suffix - 1];
  char number[rt::strings::intTextMax];
  char *digits = rt::strings::formatSigned(status, number + sizeof number);
  size_t n = 0;
  for (const char *c = ending == Ending::mainReturned ? mainReturned : exited; *c != '\0'; ++c)
    cause[n++] = *c;
  for (char *d = digits; d != number + sizeof number; ++d)
    cause[n++] = *d;
  for (char c : suffix)
    if (c != '\0')
      cause[n++] = c;
  idris_rt_crash(cause, n);
}

int64_t argumentCount() { return argumentTotal; }

const idris_rt_str *argument(int64_t i) {
  const char *text = i >= 0 && i < argumentTotal ? argumentText[i] : "";
  return idris_rt_str_from_bytes(text, strlen(text));
}

} // namespace rt::start

// The program's entry, which @main calls with the program, the
// IDRIS_RT_CPU_FEATURES bits its target enables (cpu_features.h), and its
// own argc and argv, which the runtime keeps for idris_rt_io_arg_count and
// idris_rt_io_arg. First, when the system's page size is not the target's
// the runtime is built for, it names both and ends the process with
// IDRIS_RT_CRASHED: before the processor test and before any reservation, a
// runtime built for another page size must not run at all. When the
// processor lacks one of the features, it names them, a bit no feature names
// by its number, and ends the process with IDRIS_RT_CRASHED before the
// program runs; it is compiled for the target's baseline, and idris-mlir
// keeps it there. Otherwise it points GMP at the runtime's allocator
// (idris_rt_gmp_init) and runs body on the reserved stack
// (idris_rt_run_on_stack); when that stack runs out,
// the output written so far is flushed and the process ends as a crash whose
// cause is "stack exhausted".
// What body returns is the exit status: it returns a status from 0 to 255,
// and ends the process as a crash that names any other value, which no
// parent could tell from its low 8 bits.
extern "C" [[gnu::noinline]] IDRIS_RT_BASELINE int
idris_rt_start(int64_t (*body)(void), uint64_t cpu, int argc, char **argv) {
  rt::platform::checkPageSize();
  checkCpu(cpu);
  argumentTotal = argc;
  argumentText = argv;
  idris_rt_gmp_init();
  Program program{body, 0};
  if (idris_rt_run_on_stack(runProgram, &program, programExhausted) != 0) {
    static constexpr char cause[] = "no stack could be reserved for the program";
    idris_rt_crash(cause, sizeof cause - 1);
  }
  rt::start::checkStatus(program.status, rt::start::Ending::mainReturned);
  return static_cast<int>(program.status);
}
