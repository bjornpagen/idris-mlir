// rt.alloc:classes: the allocation entry points over snmalloc, one per size
// class, and the general ones. snmalloc::alloc<S>() fixes the size class at
// compile time, so after LTO an allocation inlines into generated code as a
// thread-local free-list pop, and a free as a pagemap lookup and a push.
//
// snmalloc is configured at compile time only (runtime/CMakeLists.txt): size
// classes step by 8 bytes, no thread teardown that needs a static destructor
// or the C++ runtime, and its own small STL instead of the C++ library's.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <snmalloc/snmalloc.h>

export module rt.alloc:classes;

import :cells;

static_assert(snmalloc::DefaultPal::address_bits <= rt::alloc::heapAddressBits,
              "every heap address fits the bits the dying list keeps");

#define IDRIS_RT_DEFINE_SIZE_CLASS(S)                                                     \
  static_assert(snmalloc::sizeclass_to_size(snmalloc::size_to_sizeclass_const(S)) == (S), \
                "each entry is exactly one snmalloc size class");                         \
  extern "C" void *idris_rt_alloc_##S(void) { return snmalloc::alloc<S>(); }             \
  extern "C" void idris_rt_free_##S(void *block) { snmalloc::dealloc<S>(block); }

IDRIS_RT_SIZE_CLASSES(IDRIS_RT_DEFINE_SIZE_CLASS)

#undef IDRIS_RT_DEFINE_SIZE_CLASS

extern "C" void *idris_rt_alloc(size_t size) { return snmalloc::alloc(size); }

extern "C" void idris_rt_free(void *block) { snmalloc::dealloc(block); }
