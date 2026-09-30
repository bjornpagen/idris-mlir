// The platform layer on a POSIX system: Linux and macOS alike.
// PIN(runtime-quarantine) — see PINS.md

#include "platform.h"

#include <pthread.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <unistd.h>

namespace {

void (*faultHandler)(uintptr_t) = nullptr;
// The actions the handler replaced: a fault it does not claim goes to them.
struct sigaction previousSegv {};
struct sigaction previousBus {};

// A stack running into its guard is SIGSEGV on Linux and may be SIGBUS on
// macOS, so both are caught.
void onSignal(int signal, siginfo_t *info, void *) {
  faultHandler(reinterpret_cast<uintptr_t>(info->si_addr));
  sigaction(signal, signal == SIGBUS ? &previousBus : &previousSegv, nullptr);
}

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

namespace rt::platform {

size_t pageSize() noexcept { return static_cast<size_t>(sysconf(_SC_PAGESIZE)); }

char *reserve(size_t size) noexcept {
  int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#ifdef MAP_NORESERVE
  // Linux would otherwise count the whole region against overcommit.
  flags |= MAP_NORESERVE;
#endif
  void *region = mmap(nullptr, size, PROT_READ | PROT_WRITE, flags, -1, 0);
  return region == MAP_FAILED ? nullptr : static_cast<char *>(region);
}

bool protect(char *p, size_t n) noexcept { return mprotect(p, n, PROT_NONE) == 0; }

void release(char *p, size_t size) noexcept { munmap(p, size); }

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

void useSignalStack(char *p, size_t n) noexcept {
  stack_t alternate{};
  alternate.ss_sp = p;
  alternate.ss_size = n;
  sigaltstack(&alternate, nullptr);
}

void catchFaults(void (*onFault)(uintptr_t address)) noexcept {
  bool installed = faultHandler != nullptr;
  faultHandler = onFault;
  if (installed)
    return;
  struct sigaction action {};
  action.sa_sigaction = onSignal;
  action.sa_flags = SA_SIGINFO | SA_ONSTACK;
  sigemptyset(&action.sa_mask);
  sigaction(SIGSEGV, &action, &previousSegv);
  sigaction(SIGBUS, &action, &previousBus);
}

size_t stackLimit() noexcept {
  rlimit limit{};
  if (getrlimit(RLIMIT_STACK, &limit) != 0)
    return 0;
  return limit.rlim_cur == RLIM_INFINITY ? SIZE_MAX : static_cast<size_t>(limit.rlim_cur);
}

} // namespace rt::platform
