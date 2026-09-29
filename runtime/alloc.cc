// Allocation entry points over snmalloc, one per size class, and cells: the
// memory the runtime counts while it lives.
// snmalloc::alloc<S>() fixes the size class at
// compile time, so after LTO an allocation inlines into generated code as a
// thread-local free-list pop, and a free as a pagemap lookup and a push.
//
// snmalloc is configured at compile time only (runtime/CMakeLists.txt): size
// classes step by 8 bytes, no thread teardown that needs a static destructor
// or the C++ runtime, and its own small STL instead of the C++ library's.
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

namespace {

// The calling thread's live cells. Per thread, so that counting stays plain
// arithmetic without a data race: a program has one thread, and the folders
// may run on several in the compiler's tools, which never read the count.
thread_local uint64_t liveCells = 0;

[[noreturn]] void outOfMemory() {
  static constexpr char message[] = "idris runtime: out of memory\n";
  idris_rt_crash(message, sizeof message - 1);
}

} // namespace

void *rt::allocate(size_t size) {
  if (arenaActive)
    return idris_rt_arena_alloc(size);
  void *block = idris_rt_alloc(size);
  if (block == nullptr)
    outOfMemory();
  return block;
}

void rt::release(void *block) {
  if (!arenaActive)
    idris_rt_free(block);
}

void *rt::newCell(size_t size, uint32_t info) {
  // An evaluation child's cells are persistent: its arena is never freed.
  uint32_t count = arenaActive ? 0 : 1;
  auto *cell = static_cast<idris_rt_header *>(allocate(size));
  *cell = idris_rt_header{count, info};
  liveCells += count;
  return cell;
}

void rt::freeCell(void *cell) {
  --liveCells;
  idris_rt_free(cell);
}

extern "C" void *idris_rt_cell(size_t size, uint32_t info) { return rt::newCell(size, info); }

extern "C" uint64_t idris_rt_live_cells(void) { return liveCells; }
