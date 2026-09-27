// GMP's memory functions over the runtime's allocator (TC-RT-1;
// docs/plan.md sections 5.3 and 5.6). GMP cannot recover from a failed
// allocation, so exhausted memory ends the process here, with exit status 1
// and a message, as the other crashes do.
// PIN(runtime-quarantine) — see PINS.md

#include "idris_rt.h"

#include <string.h>
#include <unistd.h>

#include <gmp.h>

namespace {

[[noreturn]] void outOfMemory() {
  static constexpr char message[] = "idris runtime: out of memory\n";
  ssize_t written = write(2, message, sizeof message - 1);
  static_cast<void>(written);
  _exit(1);
}

void *allocate(size_t size) {
  void *block = idris_rt_alloc(size);
  if (block == nullptr)
    outOfMemory();
  return block;
}

void *reallocate(void *block, size_t oldSize, size_t newSize) {
  void *moved = allocate(newSize);
  memcpy(moved, block, oldSize < newSize ? oldSize : newSize);
  idris_rt_free(block);
  return moved;
}

void release(void *block, size_t) { idris_rt_free(block); }

} // namespace

extern "C" void idris_rt_gmp_init(void) { mp_set_memory_functions(allocate, reallocate, release); }
