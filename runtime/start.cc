// The program's entry and the reserved-stack runner. A program's main calls
// idris_rt_start, which checks the CPU and runs the program on a reserved
// stack, so that running out of it is a named crash rather than a bare
// SIGSEGV that loses the buffered output. idris-mlir-cc and compile-time
// evaluation's child run on the same runner, with stacks of their own sizes.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <cpuid.h>
#include <pthread.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <unistd.h>

namespace {

// The runner's state, which its signal handler reads. One runner runs at a
// time in a process: the program's, idris-mlir-cc's, or, after a fork, the
// evaluation child's, which replaces its parent's.
uintptr_t guardLow = 0;
uintptr_t guardHigh = 0;
void (*onExhausted)(void) = nullptr;
// The actions the handler replaced, installed once per process: the
// evaluation child inherits its parent's handler and keeps its parent's
// fallback.
bool installed = false;
struct sigaction previousSegv {};
struct sigaction previousBus {};

// A fault on the guard is the stack running out. Any other fault is not the
// runner's: the handler puts back the action it replaced, and the faulting
// instruction, run again, reaches that one.
void onFault(int signal, siginfo_t *info, void *) {
  auto address = reinterpret_cast<uintptr_t>(info->si_addr);
  if (address >= guardLow && address < guardHigh)
    onExhausted();
  sigaction(signal, signal == SIGBUS ? &previousBus : &previousSegv, nullptr);
}

// The signal handler's own stack, below the guard, so that the stack it
// reports on cannot have grown over it. A megabyte of address space, of
// which a handler touches a few pages; the fallback action, LLVM's crash
// report in idris-mlir-cc, runs on it too.
constexpr size_t alternateSize = size_t{1} << 20;
constexpr size_t smallest = size_t{1} << 26;

struct Task {
  void (*fn)(void *);
  void *arg;
  char *alternate;
};

void *runTask(void *argument) {
  auto &task = *static_cast<Task *>(argument);
  stack_t alternate{};
  alternate.ss_sp = task.alternate;
  alternate.ss_size = alternateSize;
  sigaltstack(&alternate, nullptr);
  task.fn(task.arg);
  return nullptr;
}

void install() {
  if (installed)
    return;
  struct sigaction action {};
  action.sa_sigaction = onFault;
  action.sa_flags = SA_SIGINFO | SA_ONSTACK;
  sigemptyset(&action.sa_mask);
  sigaction(SIGSEGV, &action, &previousSegv);
  sigaction(SIGBUS, &action, &previousBus);
  installed = true;
}

// A program's stack: a gibibyte, which lets a non-tail recursion go tens of
// millions deep, or the process's stack limit (ulimit -s) when that is
// larger. An unlimited one means as large as the address space allows.
size_t programStack() {
  constexpr size_t gibibyte = size_t{1} << 30;
  rlimit limit{};
  if (getrlimit(RLIMIT_STACK, &limit) != 0)
    return gibibyte;
  if (limit.rlim_cur == RLIM_INFINITY)
    return size_t{1} << 44;
  return limit.rlim_cur > gibibyte ? static_cast<size_t>(limit.rlim_cur) : gibibyte;
}

// What the program's runner does when its stack runs out: what a crash does,
// from the signal handler, where writing and exiting are safe.
[[noreturn]] void programExhausted() {
  static constexpr char message[] = "idris-mlir: stack exhausted\n";
  idris_rt_flush();
  rt::writeAll(2, message, sizeof message - 1);
  _exit(IDRIS_RT_CRASHED);
}

struct Program {
  int32_t (*body)(void);
  int32_t status;
};

void runProgram(void *argument) {
  auto &program = *static_cast<Program *>(argument);
  program.status = program.body();
}

// The CPU test runs before anything that may use the features it tests, so
// it and what it calls are compiled for the x86-64 baseline: always inlined
// into idris_rt_start, which idris-mlir-cc leaves at the baseline.
struct Cpuid {
  uint32_t reg[4];
};

[[gnu::always_inline]] inline Cpuid cpuid(uint32_t leaf) {
  Cpuid r{};
  if (__get_cpuid_count(leaf, 0, &r.reg[0], &r.reg[1], &r.reg[2], &r.reg[3]) == 0)
    return Cpuid{};
  return r;
}

// The register state the operating system saves: a vector feature is usable
// only when it saves the registers the feature uses.
[[gnu::always_inline]] inline uint64_t savedState(const Cpuid &leaf1) {
  constexpr uint32_t osxsave = 1u << 27;
  if ((leaf1.reg[2] & osxsave) == 0)
    return 0;
  uint32_t low = 0, high = 0;
  asm volatile("xgetbv" : "=a"(low), "=d"(high) : "c"(0));
  return static_cast<uint64_t>(high) << 32 | low;
}

[[gnu::always_inline]] inline uint64_t cpuFeatures() {
  Cpuid leaf1 = cpuid(1), leaf7 = cpuid(7), extended = cpuid(0x80000001);
  uint64_t state = savedState(leaf1);
  // SSE and AVX registers; then the AVX-512 mask and upper registers too.
  constexpr uint64_t avxState = 0x6, avx512State = 0xE6;
  uint64_t features = 0;
#define IDRIS_RT_CPU_TEST(bit, name, leaf, word, wordBit, needs)                                  \
  {                                                                                             \
    const Cpuid &r = (leaf) == 1 ? leaf1 : (leaf) == 7 ? leaf7 : extended;                       \
    uint64_t wanted = (needs) == 2 ? avx512State : (needs) == 1 ? avxState : 0;                  \
    if ((r.reg[word] >> (wordBit) & 1) != 0 && (state & wanted) == wanted)                         \
      features |= uint64_t{1} << (bit);                                                         \
  }
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_TEST)
#undef IDRIS_RT_CPU_TEST
  return features;
}

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

// Names what the CPU lacks, and ends the process as a crash does, before
// the program has written anything.
[[gnu::always_inline]] inline void checkCpu(uint64_t required) {
  uint64_t missing = required & ~cpuFeatures();
  if (missing == 0)
    return;
  static constexpr char prefix[] = "idris-mlir: this CPU lacks";
  static constexpr char suffix[] =
      ", which the program was compiled to use (idris-mlir-cc --cpu)\n";
  say(prefix, sizeof prefix - 1);
#define IDRIS_RT_CPU_NAME(bit, name, leaf, word, wordBit, needs)                                  \
  if ((missing >> (bit) & 1) != 0) {                                                            \
    say(" ", 1);                                                                                \
    say(name, length(name));                                                                    \
  }
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_NAME)
#undef IDRIS_RT_CPU_NAME
  say(suffix, sizeof suffix - 1);
  _exit(IDRIS_RT_CRASHED);
}

} // namespace

extern "C" int idris_rt_run_on_stack(void (*fn)(void *), void *arg, size_t most, size_t guard,
                                     void (*exhausted)(void)) {
  for (size_t size = most; size >= smallest; size >>= 1) {
    void *reserved = mmap(nullptr, size, PROT_READ | PROT_WRITE,
                          MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (reserved == MAP_FAILED)
      continue;
    auto *base = static_cast<char *>(reserved);
    char *stack = base + alternateSize + guard;
    if (mprotect(base + alternateSize, guard, PROT_NONE) != 0) {
      munmap(reserved, size);
      continue;
    }
    guardLow = reinterpret_cast<uintptr_t>(base + alternateSize);
    guardHigh = guardLow + guard;
    onExhausted = exhausted;
    install();
    Task task{fn, arg, base};
    pthread_attr_t attributes;
    pthread_t thread;
    if (pthread_attr_init(&attributes) != 0) {
      munmap(reserved, size);
      return -1;
    }
    bool started = pthread_attr_setstack(&attributes, stack, size - alternateSize - guard) == 0 &&
                   pthread_create(&thread, &attributes, runTask, &task) == 0;
    pthread_attr_destroy(&attributes);
    if (!started) {
      munmap(reserved, size);
      continue;
    }
    pthread_join(thread, nullptr);
    guardLow = guardHigh = 0;
    munmap(reserved, size);
    return 0;
  }
  return -1;
}

extern "C" [[gnu::noinline, clang::annotate("idris-rt-baseline")]] int32_t idris_rt_start(int32_t (*body)(void), uint64_t cpu) {
  checkCpu(cpu);
  Program program{body, 0};
  if (idris_rt_run_on_stack(runProgram, &program, programStack(), size_t{1} << 20,
                            programExhausted) != 0) {
    static constexpr char message[] = "idris-mlir: no stack could be reserved for the program\n";
    idris_rt_crash(message, sizeof message - 1);
  }
  return program.status;
}
