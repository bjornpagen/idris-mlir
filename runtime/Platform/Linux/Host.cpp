// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a Linux host decides, which only Linux says how to read: a fixed
// reservation that never lands on a mapping, where the address space is
// free, how much memory the process's cgroup lets it reach before the
// kernel's killer ends it (its own files, read by Posix/Cgroups.cpp), and
// what the kernel's signal frame takes, each read once, at start; and where
// the C library put a thread's guard.
#include "Platform/Platform.h"

#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/auxv.h>
#include <sys/mman.h>
#include <sys/sysinfo.h>
#include <unistd.h>

namespace rt::platform {

// MAP_FIXED_NOREPLACE refuses a place a mapping holds (EEXIST). A kernel
// before 4.17 takes the flag for a hint and maps elsewhere, which is as
// occupied.
Placed reserveAt(char *at, size_t size) noexcept {
  void *got = mmap(at, size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
  if (got == at)
    return Placed::Reserved;
  if (got != MAP_FAILED) {
    munmap(got, size);
    return Placed::Occupied;
  }
  return errno == EEXIST ? Placed::Occupied : Placed::Refused;
}

// The kernel maps new regions downward from below the initial stack, so the
// space above the program's break is free up to them: the heap starts at
// the first aligned address above it and grows up, past whatever it meets.
// User space ends at the power of two above the initial stack, which the
// kernel places at its top; and no further than the process's address-space
// limit (`ulimit -v`), which counts every mapping.
Span heapSpan(size_t alignment) noexcept {
  auto brk = reinterpret_cast<uintptr_t>(sbrk(0));
  uintptr_t base = roundUp(brk, alignment);
  char local = 0;
  uintptr_t stack = reinterpret_cast<uintptr_t>(&local);
  uintptr_t top = uintptr_t{1} << (64 - __builtin_clzll(stack));
  size_t length = top > base ? top - base : 0;
  size_t limit = addressSpaceLimit();
  return {reinterpret_cast<char *>(base), limit < length ? limit : length};
}

size_t commitLimit() noexcept { return cgroupLimit(hostRoot); }

// Linux's stat names its times as POSIX does, st_atim and its kin.
StatTimes statTimes(const struct stat &status) noexcept {
  return {status.st_atim, status.st_mtim, status.st_ctim};
}

size_t physicalMemory() noexcept {
  struct sysinfo system {};
  if (sysinfo(&system) != 0)
    return SIZE_MAX;
  return static_cast<size_t>(system.totalram) * system.mem_unit;
}

// The kernel says what its signal frame takes in the auxiliary vector
// (AT_MINSIGSTKSZ, entry 51 of its ABI), which grows with the registers a
// processor saves; a kernel that says nothing takes the C library's
// minimum.
size_t signalStackMinimum() noexcept {
  constexpr unsigned long minimumSignalStackEntry = 51;
  unsigned long kernel = getauxval(minimumSignalStackEntry);
  return kernel != 0 ? static_cast<size_t>(kernel) : static_cast<size_t>(MINSIGSTKSZ);
}

// The C library reports a thread's stack without its guard, which lies
// just below it; a thread whose attributes it cannot read claims no fault.
Guard libraryGuard() noexcept {
  pthread_attr_t attributes;
  if (pthread_getattr_np(pthread_self(), &attributes) != 0)
    return {0, 0};
  void *low = nullptr;
  size_t size = 0, guard = 0;
  pthread_attr_getstack(&attributes, &low, &size);
  pthread_attr_getguardsize(&attributes, &guard);
  pthread_attr_destroy(&attributes);
  auto bottom = reinterpret_cast<uintptr_t>(low);
  return {bottom - guard, bottom};
}

} // namespace rt::platform
