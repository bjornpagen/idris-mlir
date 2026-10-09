// rt.alloc:cells: cells, the memory the runtime counts while it lives.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

export module rt.alloc:cells;

import :blocks;

namespace {

// The calling thread's live cells. Per thread, so that counting stays plain
// arithmetic without a data race: a program has one thread, and the
// compiler's folders, which may run on several, read it around each fold,
// on their own thread.
thread_local uint64_t liveCells = 0;

} // namespace

export namespace rt::alloc {

// No heap address the allocator hands out has more bits than this: its
// pagemap covers no more (:classes checks snmalloc against it). The dying
// list of rt.rc keeps an address in that many bits.
inline constexpr unsigned heapAddressBits = 48;

// A cell of `size` bytes with the header {1, info}, counted as live; in an
// evaluation child, from the arena with the header {0, info}: persistent, and
// not counted. Exhausted memory is a crash.
void *newCell(size_t size, uint32_t info) {
  // An evaluation child's cells are persistent: its arena is never freed.
  uint32_t count = arenaActive ? 0 : 1;
  auto *cell = static_cast<idris_rt_header *>(allocate(size));
  *cell = idris_rt_header{count, info};
  liveCells += count;
  return cell;
}

// Frees the memory of a counted heap cell, which an evaluation child never
// has, and stops counting it.
void freeCell(void *cell) {
  --liveCells;
  idris_rt_free(cell);
}

} // namespace rt::alloc

extern "C" void *idris_rt_cell(size_t size, uint32_t info) { return rt::alloc::newCell(size, info); }

extern "C" uint64_t idris_rt_live_cells(void) { return liveCells; }
