// rt.start:entry: the program's entry, idris_rt_start: the processor test,
// the program's arguments, its stack, and its exit status.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "cpu_features.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

export module rt.start:entry;

// rt.io reads the program's arguments from here, so rt.start does not import it.
import rt.platform;
import rt.strings;

namespace {

// The arguments main received, which idris_rt_start keeps before the
// program runs.
int argumentTotal = 0;
char **argumentText = nullptr;

// A program's stack: the number of bytes IDRIS_RT_STACK says, when it is
// set; else a gibibyte, which lets a non-tail recursion go tens of millions
// deep, or the process's stack limit (ulimit -s) when that is larger. An
// unlimited one means as large as the address space allows.
size_t programStack() {
  constexpr size_t gibibyte = size_t{1} << 30;
  if (const char *text = getenv("IDRIS_RT_STACK")) {
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
  if (limit == SIZE_MAX)
    return size_t{1} << 44;
  return limit > gibibyte ? limit : gibibyte;
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
// tests, so it and what it calls stay compiled for the target's baseline:
// they are always inlined into idris_rt_start, or annotated as it is.
[[gnu::always_inline]] inline void say(const char *text, size_t n) {
  while (n > 0) {
    ssize_t written = write(2, text, n);
    if (written <= 0)
      return;
    text += written;
    n -= static_cast<size_t>(written);
  }
}

[[gnu::always_inline]] inline size_t length(const char *text) {
  size_t n = 0;
  while (text[n] != '\0')
    ++n;
  return n;
}

// Names what the processor lacks, and ends the process as a crash does,
// before the program has written anything.
[[gnu::always_inline]] inline void checkCpu(uint64_t required) {
  uint64_t missing = required & ~rt::platform::cpuFeatures();
  if (missing == 0)
    return;
  static constexpr char prefix[] = "idris-mlir: this processor lacks";
  static constexpr char suffix[] =
      ", which the program was compiled to use\n";
  say(prefix, sizeof prefix - 1);
#define IDRIS_RT_CPU_NAME(bit, test, name)                                                       \
  if ((missing >> (bit) & 1) != 0) {                                                             \
    say(" ", 1);                                                                                 \
    say(name, length(name));                                                                     \
  }
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_NAME)
#undef IDRIS_RT_CPU_NAME
  say(suffix, sizeof suffix - 1);
  _exit(IDRIS_RT_CRASHED);
}

// What the program's runner does when its stack runs out: what a crash does,
// from the fault handler, where writing and exiting are safe.
[[noreturn]] void programExhausted() {
  static constexpr char message[] = "idris-mlir: stack exhausted\n";
  idris_rt_flush();
  say(message, sizeof message - 1);
  _exit(IDRIS_RT_CRASHED);
}

} // namespace

export namespace rt::start {

// What ended the program with a status, which its crash names.
enum class Ending { mainReturned, exited };

// A parent sees only the low 8 bits of an exit status, so 256 would read as
// success and -1 as 255. A status outside 0 to 255 is one the process
// cannot report, whether main returned it or the program exited with it, and
// ends it as a crash that says so.
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

// A new string of argument i, whose bytes are decoded as any bytes from
// outside the program are; the empty string when there is no argument i.
const idris_rt_str *argument(int64_t i) {
  const char *text = i >= 0 && i < argumentTotal ? argumentText[i] : "";
  return idris_rt_str_from_bytes(text, length(text));
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
  Program program{body, 0};
  if (idris_rt_run_on_stack(runProgram, &program, programStack(), size_t{1} << 20,
                            programExhausted) != 0) {
    static constexpr char message[] = "idris-mlir: no stack could be reserved for the program\n";
    idris_rt_crash(message, sizeof message - 1);
  }
  rt::start::checkStatus(program.status, rt::start::Ending::mainReturned);
  return static_cast<int>(program.status);
}
