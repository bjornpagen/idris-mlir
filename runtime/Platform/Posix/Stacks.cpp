// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Running on a stack of the runtime's own, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"

#include <pthread.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/resource.h>

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

size_t stackLimit() noexcept {
  rlimit limit{};
  if (getrlimit(RLIMIT_STACK, &limit) != 0)
    return 0;
  return limit.rlim_cur == RLIM_INFINITY ? SIZE_MAX : static_cast<size_t>(limit.rlim_cur);
}

} // namespace rt::platform
