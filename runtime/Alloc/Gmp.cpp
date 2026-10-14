// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// GMP's memory functions over the runtime's allocator. GMP cannot recover
// from a failed allocation; rt::alloc::allocate ends the process with a
// crash instead of returning.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "idris_rt.h"

#include <stddef.h>
#include <string.h>

#include <atomic>

#include <gmp.h>

namespace {

void *allocate(size_t size) { return rt::alloc::allocate(size); }

void *reallocate(void *block, size_t oldSize, size_t newSize) {
  void *moved = rt::alloc::allocate(newSize);
  memcpy(moved, block, oldSize < newSize ? oldSize : newSize);
  rt::alloc::release(block);
  return moved;
}

void release(void *block, size_t) { rt::alloc::release(block); }

// 0: not yet, 1: being set, 2: set. Constant-initialized, so no constructor.
std::atomic<int> gmpState{0};

} // namespace

extern "C" void idris_rt_gmp_init(void) { mp_set_memory_functions(allocate, reallocate, release); }

namespace rt::alloc {

void gmpReady() {
  if (gmpState.load(std::memory_order_acquire) == 2) [[likely]]
    return;
  int expected = 0;
  if (gmpState.compare_exchange_strong(expected, 1, std::memory_order_acq_rel)) {
    idris_rt_gmp_init();
    gmpState.store(2, std::memory_order_release);
    return;
  }
  while (gmpState.load(std::memory_order_acquire) != 2) {
  }
}

} // namespace rt::alloc
