// Cells, the memory the runtime counts while it lives.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace {

// The calling thread's live cells. Per thread, so that counting stays plain
// arithmetic without a data race: a program has one thread, and the
// compiler's folders, which may run on several, read it around each fold,
// on their own thread.
thread_local uint64_t liveCells = 0;

} // namespace

namespace rt::alloc {

void *newCell(size_t size, uint32_t info) {
  auto *cell = static_cast<idris_rt_header *>(allocate(size));
  *cell = idris_rt_header{1, info};
  ++liveCells;
  return cell;
}

void freeCell(void *cell) {
  --liveCells;
  idris_rt_free(cell);
}

} // namespace rt::alloc

extern "C" void *idris_rt_cell(size_t size, uint32_t info) { return rt::alloc::newCell(size, info); }

extern "C" uint64_t idris_rt_live_cells(void) { return liveCells; }
