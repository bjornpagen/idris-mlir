// rt.platform:stacks: running on a stack of the runtime's own, on a POSIX
// system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <pthread.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/resource.h>

export module rt.platform:stacks;

namespace {

struct Thread {
  void (*fn)(void *);
  void *arg;
};

void *startThread(void *argument) {
  auto &thread = *static_cast<Thread *>(argument);
  thread.fn(thread.arg);
  return nullptr;
}

} // namespace

export namespace rt::platform {

// Runs fn(arg) on a new thread whose stack is the `size` bytes at `stack`,
// and returns once it has; false when no thread could start, and fn did
// not run.
bool runThread(void (*fn)(void *), void *arg, char *stack, size_t size) noexcept {
  Thread thread{fn, arg};
  pthread_attr_t attributes;
  if (pthread_attr_init(&attributes) != 0)
    return false;
  pthread_t id;
  bool started = pthread_attr_setstack(&attributes, stack, size) == 0 &&
                 pthread_create(&id, &attributes, startThread, &thread) == 0;
  pthread_attr_destroy(&attributes);
  if (started)
    pthread_join(id, nullptr);
  return started;
}

// Makes the n bytes at p the calling thread's stack for signal handlers.
void useSignalStack(char *p, size_t n) noexcept {
  stack_t alternate{};
  alternate.ss_sp = p;
  alternate.ss_size = n;
  sigaltstack(&alternate, nullptr);
}

// The process's stack limit in bytes: SIZE_MAX when it has none, 0 when it
// cannot be read.
size_t stackLimit() noexcept {
  rlimit limit{};
  if (getrlimit(RLIMIT_STACK, &limit) != 0)
    return 0;
  return limit.rlim_cur == RLIM_INFINITY ? SIZE_MAX : static_cast<size_t>(limit.rlim_cur);
}

} // namespace rt::platform
