// rt.alloc:blocks: raw memory, which is not a cell (GMP's scratch integers,
// scratch buffers): from compile-time evaluation's arena in an evaluation
// child, from snmalloc otherwise.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>

export module rt.alloc:blocks;

namespace {

[[noreturn]] void outOfMemory() {
  static constexpr char message[] = "idris runtime: out of memory\n";
  idris_rt_crash(message, sizeof message - 1);
}

} // namespace

export namespace rt::alloc {

// True in an evaluation child once idris_rt_eval_begin ran: every allocation
// then comes from the arena, every cell is persistent, and nothing is freed.
inline bool arenaActive = false;

// Exhausted memory is a crash.
void *allocate(size_t size) {
  if (arenaActive)
    return idris_rt_arena_alloc(size);
  void *block = idris_rt_alloc(size);
  if (block == nullptr)
    outOfMemory();
  return block;
}

void release(void *block) {
  if (!arenaActive)
    idris_rt_free(block);
}

} // namespace rt::alloc
