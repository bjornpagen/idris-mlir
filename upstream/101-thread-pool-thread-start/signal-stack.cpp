// A pool whose strategy installs an alternate signal stack on each thread
// it starts: a task that overflows its thread's stack reaches the
// process's handler for the fault, which runs on that signal stack and
// prints "ok". At the pin, with no hook, no worker has a signal stack and
// the process dies of the fault, the handler never running.
// Built against the toolchain's LLVMSupport:
//   clang++ -std=c++17 signal-stack.cpp $(llvm-config --cxxflags --ldflags --libs support --system-libs)
#include "llvm/Support/ThreadPool.h"
#include "llvm/Support/Threading.h"
#include <csignal>
#include <cstdlib>
#include <unistd.h>

// The fault's handler: async-signal-safe, it says the handler ran.
static void caught(int) {
  static const char ok[] = "ok\n";
  (void)!write(STDOUT_FILENO, ok, sizeof(ok) - 1);
  _exit(0);
}

// Each worker's alternate signal stack, as LLVM sizes its own.
static void installSignalStack() {
  stack_t stack = {};
  stack.ss_size = MINSIGSTKSZ + 64 * 1024;
  stack.ss_sp = std::malloc(stack.ss_size);
  if (stack.ss_sp == nullptr || sigaltstack(&stack, nullptr) != 0)
    _exit(2);
}

// A recursion that touches every page of each frame, so that it reaches
// the guard below the stack, whatever its size, without stepping over it.
[[gnu::noinline]] static int deep(int depth) {
  volatile char frame[1024];
  frame[0] = static_cast<char>(depth);
  frame[sizeof(frame) - 1] = static_cast<char>(depth);
  return deep(depth + 1) + frame[0] + frame[sizeof(frame) - 1];
}

int main() {
  struct sigaction action = {};
  action.sa_handler = caught;
  action.sa_flags = SA_ONSTACK;
  sigemptyset(&action.sa_mask);
  // A stack guard's fault is SIGSEGV on Linux and SIGBUS or SIGSEGV on
  // Darwin.
  if (sigaction(SIGSEGV, &action, nullptr) != 0 ||
      sigaction(SIGBUS, &action, nullptr) != 0)
    return 2;
  llvm::ThreadPoolStrategy strategy = llvm::hardware_concurrency(1);
  strategy.StackSizeInBytes = 256 * 1024;
  strategy.OnThreadStart = installSignalStack;
  llvm::StdThreadPool pool(strategy);
  pool.async([] { (void)deep(0); });
  pool.wait();
  return 1;
}
