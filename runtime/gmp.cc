// GMP's memory functions over the runtime's allocator. GMP cannot recover from
// a failed allocation; rt::allocate ends the process with a crash (or, in an
// evaluation child, reports exhaustion) instead of returning.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <atomic>

#include <gmp.h>
#include <string.h>

namespace {

void *allocate(size_t size) { return rt::allocate(size); }

void *reallocate(void *block, size_t oldSize, size_t newSize) {
  void *moved = rt::allocate(newSize);
  memcpy(moved, block, oldSize < newSize ? oldSize : newSize);
  rt::release(block);
  return moved;
}

void release(void *block, size_t) { rt::release(block); }

// 0: not yet, 1: being set, 2: set. Constant-initialized, so no constructor.
std::atomic<int> gmpState{0};

} // namespace

extern "C" void idris_rt_gmp_init(void) { mp_set_memory_functions(allocate, reallocate, release); }

void rt::gmpReady() {
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
