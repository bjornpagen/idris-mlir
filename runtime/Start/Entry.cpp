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

// A program's stack: the number of bytes IDRIS_RT_STACK says, when it is
// set; else a gibibyte, which lets a non-tail recursion go tens of millions
// deep, or the process's stack limit (ulimit -s) when that is larger, up to
// 2^44 bytes: a quarter of the address space Darwin grants a process, so
// that the heap keeps the rest. An unlimited limit, larger than any, is
// that ceiling, and one the system cannot report, 0, raises nothing.
size_t programStack() {
  constexpr size_t gibibyte = size_t{1} << 30;
  constexpr size_t ceiling = size_t{1} << 44;
  if (const char *text = rt::platform::environment("IDRIS_RT_STACK")) {
    size_t bytes = 0;
    bool valid = *text != '\0';
    for (; valid && *text != '\0'; ++text) {
      unsigned digit = static_cast<unsigned>(*text - '0');
      valid = digit < 10 && bytes <= (SIZE_MAX - digit) / 10;
      bytes = bytes * 10 + digit;
    }
    if (!valid || bytes == 0) {
      static constexpr char message[] =
          "idris-mlir: IDRIS_RT_STACK is not a number of bytes above 0\n";
      idris_rt_crash(message, sizeof message - 1);
    }
    return bytes;
  }
  size_t limit = rt::platform::stackLimit();
  return limit < gibibyte ? gibibyte : limit > ceiling ? ceiling : limit;
}

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
  static constexpr char prefix[] = "idris-mlir: this processor lacks";
  static constexpr char suffix[] = ", which the program was compiled to use\n";
  rt::platform::writeAll(2, prefix, sizeof prefix - 1);
#define IDRIS_RT_CPU_NAME(bit, test, name)                                                       \
  if ((missing >> (bit) & 1) != 0) {                                                             \
    rt::platform::writeAll(2, " " name, sizeof(name));                                           \
  }
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_NAME)
#undef IDRIS_RT_CPU_NAME
  // The requirement is the program's word, which may hold a bit the
  // target's list does not name (a program built against another list):
  // the processor lacks it all the same, so it is named by its number.
#define IDRIS_RT_CPU_BIT(bit, test, name) | uint64_t{1} << (bit)
  constexpr uint64_t named = 0 IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_BIT);
#undef IDRIS_RT_CPU_BIT
  for (uint64_t unnamed = missing & ~named; unnamed != 0; unnamed &= unnamed - 1) {
    static constexpr char bitText[] = " bit ";
    char digits[rt::strings::intTextMax];
    char *end = digits + sizeof digits;
    char *start = rt::strings::formatUnsigned(static_cast<uint64_t>(__builtin_ctzll(unnamed)), end);
    rt::platform::writeAll(2, bitText, sizeof bitText - 1);
    rt::platform::writeAll(2, start, static_cast<size_t>(end - start));
  }
  rt::platform::writeAll(2, suffix, sizeof suffix - 1);
  rt::platform::exitProcess(IDRIS_RT_CRASHED);
}

// What the program's runner does when its stack runs out: what a crash does,
// from the fault handler, where writing and exiting are safe.
[[noreturn]] void programExhausted() {
  static constexpr char message[] = "idris-mlir: stack exhausted\n";
  idris_rt_flush();
  rt::platform::writeAll(2, message, sizeof message - 1);
  rt::platform::exitProcess(IDRIS_RT_CRASHED);
}

} // namespace

namespace rt::start {

void checkStatus(int64_t status, Ending ending) {
  if (status >= 0 && status <= 255)
    return;
  static constexpr char mainReturned[] = "idris-mlir: main returned ";
  static constexpr char exited[] = "idris-mlir: exit with ";
  static_assert(sizeof exited <= sizeof mainReturned, "the message has room for either");
  static constexpr char suffix[] = ", which is not an exit status (0 to 255)\n";
  char message[sizeof mainReturned - 1 + rt::strings::intTextMax + sizeof suffix - 1];
  char number[rt::strings::intTextMax];
  char *digits = rt::strings::formatSigned(status, number + sizeof number);
  size_t n = 0;
  for (const char *c = ending == Ending::mainReturned ? mainReturned : exited; *c != '\0'; ++c)
    message[n++] = *c;
  for (char *d = digits; d != number + sizeof number; ++d)
    message[n++] = *d;
  for (char c : suffix)
    if (c != '\0')
      message[n++] = c;
  idris_rt_crash(message, n);
}

int64_t argumentCount() { return argumentTotal; }

const idris_rt_str *argument(int64_t i) {
  const char *text = i >= 0 && i < argumentTotal ? argumentText[i] : "";
  return idris_rt_str_from_bytes(text, strlen(text));
}

} // namespace rt::start

extern "C" [[gnu::noinline, clang::annotate("idris-rt-baseline")]] int
idris_rt_start(int64_t (*body)(void), uint64_t cpu, int argc, char **argv) {
  // Before the processor test and before any reservation: a runtime built
  // for another page size than this system's must not run at all.
  rt::platform::checkPageSize();
  checkCpu(cpu);
  argumentTotal = argc;
  argumentText = argv;
  idris_rt_gmp_init();
  Program program{body, 0};
  if (idris_rt_run_on_stack(runProgram, &program, programStack(), size_t{1} << 20,
                            programExhausted) != 0) {
    static constexpr char message[] = "idris-mlir: no stack could be reserved for the program\n";
    idris_rt_crash(message, sizeof message - 1);
  }
  rt::start::checkStatus(program.status, rt::start::Ending::mainReturned);
  return static_cast<int>(program.status);
}
