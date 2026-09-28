// Allocation entry points over snmalloc, one per size class (TC-RT-1;
// docs/plan.md section 5.6). snmalloc::alloc<S>() fixes the size class at
// compile time, so after LTO an allocation inlines into generated code as a
// thread-local free-list pop, and a free as a pagemap lookup and a push.
//
// snmalloc is configured at compile time only (runtime/CMakeLists.txt): size
// classes step by 8 bytes, thread teardown through pthread keys rather than
// the C++ runtime, and its own small STL instead of the C++ library's.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <snmalloc/snmalloc.h>

#define IDRIS_RT_DEFINE_SIZE_CLASS(S)                                                     \
  static_assert(snmalloc::sizeclass_to_size(snmalloc::size_to_sizeclass_const(S)) == (S), \
                "each entry is exactly one snmalloc size class");                         \
  extern "C" void *idris_rt_alloc_##S(void) { return snmalloc::alloc<S>(); }             \
  extern "C" void idris_rt_free_##S(void *block) { snmalloc::dealloc<S>(block); }

IDRIS_RT_SIZE_CLASSES(IDRIS_RT_DEFINE_SIZE_CLASS)

#undef IDRIS_RT_DEFINE_SIZE_CLASS

extern "C" void *idris_rt_alloc(size_t size) { return snmalloc::alloc(size); }

extern "C" void idris_rt_free(void *block) { snmalloc::dealloc(block); }

void *rt::allocate(size_t size) {
  if (arenaActive)
    return idris_rt_arena_alloc(size);
  void *block = idris_rt_alloc(size);
  if (block == nullptr) {
    static constexpr char message[] = "idris runtime: out of memory\n";
    idris_rt_crash(message, sizeof message - 1);
  }
  return block;
}

void rt::release(void *block) {
  if (!arenaActive)
    idris_rt_free(block);
}

extern "C" void *idris_rt_cell(size_t size) { return rt::allocate(size); }
