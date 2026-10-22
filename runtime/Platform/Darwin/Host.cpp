// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a Darwin host decides, which only Darwin says how to read: a fixed
// reservation that never lands on a mapping, where the address space is
// free, and what the kernel's signal frame takes. Darwin enforces no limit
// a process can read as its kill point, nor an address-space limit, so the
// heap's only bound is the address space.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"

#include <mach/vm_param.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/sysctl.h>

namespace rt::platform {

// Darwin's mmap takes the address as a hint and places a mapping elsewhere
// when the hint is taken, which is as occupied.
Placed reserveAt(char *at, size_t size) noexcept {
  void *got = mmap(at, size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
  if (got == at)
    return Placed::Reserved;
  if (got == MAP_FAILED)
    return Placed::Refused;
  munmap(got, size);
  return Placed::Occupied;
}

// Darwin maps new regions upward from the first hole that fits: a region of
// twice the alignment, placed and given back, holds an aligned one whose
// whole extent is free, and the space above it is too. User space ends at
// MACH_VM_MAX_ADDRESS.
Span heapSpan(size_t alignment) noexcept {
  void *probe = mmap(nullptr, 2 * alignment, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
  if (probe == MAP_FAILED)
    return {nullptr, 0};
  munmap(probe, 2 * alignment);
  uintptr_t base = roundUp(reinterpret_cast<uintptr_t>(probe), alignment);
  uintptr_t top = MACH_VM_MAX_ADDRESS;
  return {reinterpret_cast<char *>(base), top > base ? top - base : 0};
}

size_t commitLimit() noexcept { return SIZE_MAX; }

size_t physicalMemory() noexcept {
  uint64_t bytes = 0;
  size_t length = sizeof bytes;
  if (sysctlbyname("hw.memsize", &bytes, &length, nullptr, 0) != 0)
    return SIZE_MAX;
  return static_cast<size_t>(bytes);
}

// The SDK's minimum, which Darwin's signal frame fits.
size_t signalStackMinimum() noexcept { return MINSIGSTKSZ; }

} // namespace rt::platform
