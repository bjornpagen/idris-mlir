// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Running on a stack of the runtime's own, on a POSIX system.
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

// The slot each thread's guard is kept in, and what takes one still kept
// when its thread ends.
pthread_key_t guardSlot;
void (*guardEnd)(rt::platform::Guard *) = nullptr;

void endGuard(void *guard) { guardEnd(static_cast<rt::platform::Guard *>(guard)); }

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

void dropSignalStack() noexcept {
  stack_t none{};
  none.ss_flags = SS_DISABLE;
  sigaltstack(&none, nullptr);
}

// A thread's own slot, which the fault handler reads on the faulting thread
// without allocating: a thread that never kept a guard reads null.
bool guardsEnd(void (*atEnd)(Guard *guard)) noexcept {
  if (guardEnd == nullptr && pthread_key_create(&guardSlot, endGuard) != 0)
    return false;
  guardEnd = atEnd;
  return true;
}

void keepGuard(Guard *guard) noexcept { pthread_setspecific(guardSlot, guard); }

Guard *keptGuard() noexcept { return static_cast<Guard *>(pthread_getspecific(guardSlot)); }

// POSIX's least stack a thread may be given, which the C library sizes by
// what it keeps at the stack's top: its thread's descriptor and the static
// thread-local storage.
size_t threadStackMinimum() noexcept {
  long minimum = sysconf(_SC_THREAD_STACK_MIN);
  return minimum > 0 ? static_cast<size_t>(minimum) : 0;
}

} // namespace rt::platform
