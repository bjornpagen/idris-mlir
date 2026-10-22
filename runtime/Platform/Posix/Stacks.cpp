// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Running on a stack of the runtime's own, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"

#include <pthread.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <unistd.h>

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

namespace rt::platform {

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

// POSIX's least stack a thread may be given, which the C library sizes by
// what it keeps at the stack's top: its thread's descriptor and the static
// thread-local storage.
size_t threadStackMinimum() noexcept {
  long minimum = sysconf(_SC_THREAD_STACK_MIN);
  return minimum > 0 ? static_cast<size_t>(minimum) : 0;
}

} // namespace rt::platform
