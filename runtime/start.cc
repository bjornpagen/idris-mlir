// The program's entry and the reserved-stack runner. A program's main calls
// idris_rt_start, which checks the processor and runs the program on a
// reserved stack, so that running out of it is a named crash rather than a
// bare fault that loses the buffered output. idris-mlir-cc and compile-time
// evaluation's child run on the same runner, with stacks of their own sizes.
// What it needs of the system is in the platform layer (platform.h).
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"
#include "platform.h"

#include <unistd.h>

namespace {

// The runner's state, which the fault handler reads. One runner runs at a
// time in a process: the program's, idris-mlir-cc's, or, after a fork, the
// evaluation child's, which replaces its parent's.
uintptr_t guardLow = 0;
uintptr_t guardHigh = 0;
void (*onExhausted)(void) = nullptr;

// A fault on the guard is the stack running out. Any other fault is not the
// runner's, and returning gives it the action it had before.
void onFault(uintptr_t address) {
  if (address >= guardLow && address < guardHigh)
    onExhausted();
}

// The signal handler's own stack, below the guard, so that the stack it
// reports on cannot have grown over it. A megabyte of address space, of
// which a handler touches a few pages; the action a fault had before, LLVM's
// crash report in idris-mlir-cc, runs on it too.
constexpr size_t alternateSize = size_t{1} << 20;
constexpr size_t smallest = size_t{1} << 26;

size_t roundUp(size_t n, size_t page) { return (n + page - 1) / page * page; }

struct Task {
  void (*fn)(void *);
  void *arg;
  char *alternate;
  size_t alternateSize;
};

void runTask(void *argument) {
  auto &task = *static_cast<Task *>(argument);
  rt::platform::useSignalStack(task.alternate, task.alternateSize);
  task.fn(task.arg);
}

// A program's stack: a gibibyte, which lets a non-tail recursion go tens of
// millions deep, or the process's stack limit (ulimit -s) when that is
// larger. An unlimited one means as large as the address space allows.
size_t programStack() {
  constexpr size_t gibibyte = size_t{1} << 30;
  size_t limit = rt::platform::stackLimit();
  if (limit == SIZE_MAX)
    return size_t{1} << 44;
  return limit > gibibyte ? limit : gibibyte;
}

// What the program's runner does when its stack runs out: what a crash does,
// from the fault handler, where writing and exiting are safe.
[[noreturn]] void programExhausted() {
  static constexpr char message[] = "idris-mlir: stack exhausted\n";
  idris_rt_flush();
  rt::writeAll(2, message, sizeof message - 1);
  _exit(IDRIS_RT_CRASHED);
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
      ", which the program was compiled to use (idris-mlir-cc --cpu)\n";
  say(prefix, sizeof prefix - 1);
#define IDRIS_RT_CPU_NAME(bit, name)                                                             \
  if ((missing >> (bit) & 1) != 0) {                                                             \
    say(" ", 1);                                                                                 \
    say(name, length(name));                                                                     \
  }
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_NAME)
#undef IDRIS_RT_CPU_NAME
  say(suffix, sizeof suffix - 1);
  _exit(IDRIS_RT_CRASHED);
}

// A parent sees only the low 8 bits of an exit status, so 256 would read as
// success and -1 as 255. A status outside 0 to 255 is one the process
// cannot report, and ends it as a crash that says so.
void checkStatus(int64_t status) {
  if (status >= 0 && status <= 255)
    return;
  static constexpr char prefix[] = "idris-mlir: main returned ";
  static constexpr char suffix[] = ", which is not an exit status (0 to 255)\n";
  char message[sizeof prefix - 1 + rt::intTextMax + sizeof suffix - 1];
  char number[rt::intTextMax];
  char *digits = rt::formatSigned(status, number + sizeof number);
  size_t n = 0;
  for (char c : prefix)
    if (c != '\0')
      message[n++] = c;
  for (char *d = digits; d != number + sizeof number; ++d)
    message[n++] = *d;
  for (char c : suffix)
    if (c != '\0')
      message[n++] = c;
  idris_rt_crash(message, n);
}

} // namespace

extern "C" int idris_rt_run_on_stack(void (*fn)(void *), void *arg, size_t most, size_t guard,
                                     void (*exhausted)(void)) {
  size_t page = rt::platform::pageSize();
  size_t alternate = roundUp(alternateSize, page);
  guard = roundUp(guard, page);
  for (size_t size = most; size >= smallest; size >>= 1) {
    char *base = rt::platform::reserve(size);
    if (base == nullptr)
      continue;
    char *stack = base + alternate + guard;
    if (!rt::platform::protect(base + alternate, guard)) {
      rt::platform::release(base, size);
      continue;
    }
    guardLow = reinterpret_cast<uintptr_t>(base + alternate);
    guardHigh = guardLow + guard;
    onExhausted = exhausted;
    rt::platform::catchFaults(onFault);
    Task task{fn, arg, base, alternate};
    bool ran = rt::platform::runThread(runTask, &task, stack, size - alternate - guard);
    guardLow = guardHigh = 0;
    rt::platform::release(base, size);
    if (ran)
      return 0;
  }
  return -1;
}

extern "C" [[gnu::noinline, clang::annotate("idris-rt-baseline")]] int32_t
idris_rt_start(int64_t (*body)(void), uint64_t cpu) {
  checkCpu(cpu);
  Program program{body, 0};
  if (idris_rt_run_on_stack(runProgram, &program, programStack(), size_t{1} << 20,
                            programExhausted) != 0) {
    static constexpr char message[] = "idris-mlir: no stack could be reserved for the program\n";
    idris_rt_crash(message, sizeof message - 1);
  }
  checkStatus(program.status);
  return static_cast<int32_t>(program.status);
}
