// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's memory over snmalloc: raw blocks, and cells, which it
// counts while they live. snmalloc is included here alone, so its fast
// paths inline into newCell and freeCell in every build. Those two, the
// allocation under them and idris_rt_cell are always inlined wherever the
// runtime's bitcode is joined, every program among them: idr-lower calls
// idris_rt_cell with a constant size, so the size class folds and an
// allocation is a thread-local free-list pop in the caller, whatever the
// inliner's budget says. A unit compiled alone calls them.
//
// snmalloc is configured at compile time only (runtime/CMakeLists.txt): size
// classes step by 8 bytes, so a cell of an 8-byte header and two fields
// takes exactly 24; no thread teardown that needs a static destructor or the
// C++ runtime; and its own small STL instead of the C++ library's.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

#include <snmalloc/snmalloc.h>

static_assert(snmalloc::DefaultPal::address_bits <= rt::alloc::heapAddressBits,
              "every heap address fits the bits the dying list keeps");
// snmalloc decommits and zeroes by its own page, which must be the target
// entry's (rt::platform checks that one against the system's at startup):
// POSIX platforms take it from SNMALLOC_PAGESIZE, which the build sets to
// it, and Apple's platform has its own constant.
static_assert(snmalloc::OS_PAGE_SIZE == IDRIS_RT_PAGE_SIZE,
              "snmalloc's page is the target entry's page");
static_assert(snmalloc::sizeclass_to_size(snmalloc::size_to_sizeclass_const(24)) == 24,
              "a header and two fields are one size class, with no slack");

namespace {

// The calling thread's live cells. Per thread, so that counting stays plain
// arithmetic without a data race: a program has one thread, and the
// compiler's folders, which may run on several, read it around each fold,
// on their own thread.
thread_local uint64_t liveCells = 0;

} // namespace

namespace rt::alloc {

void outOfMemory() {
  static constexpr char message[] = "idris runtime: out of memory\n";
  idris_rt_crash(message, sizeof message - 1);
}

[[gnu::always_inline]] void *allocate(size_t size) {
  void *block = snmalloc::alloc(size);
  if (block == nullptr) [[unlikely]]
    outOfMemory();
  return block;
}

// snmalloc keeps the block when the new size is in its size class, which
// is most of what GMP's growing integers ask. GMP never asks for 0 bytes,
// the one size for which realloc frees and gives null.
void *reallocate(void *block, size_t size) {
  void *moved = snmalloc::libc::realloc(block, size);
  if (moved == nullptr) [[unlikely]]
    outOfMemory();
  return moved;
}

void release(void *block) { snmalloc::dealloc(block); }

[[gnu::always_inline]] void *newCell(size_t size, uint32_t info) {
  auto *cell = static_cast<idris_rt_header *>(allocate(size));
  *cell = idris_rt_header{1, info};
  ++liveCells;
  return cell;
}

[[gnu::always_inline]] void freeCell(void *cell) {
  --liveCells;
  snmalloc::dealloc(cell);
}

} // namespace rt::alloc

extern "C" [[gnu::always_inline]] void *idris_rt_cell(size_t size, uint32_t info) {
  return rt::alloc::newCell(size, info);
}

extern "C" uint64_t idris_rt_live_cells(void) { return liveCells; }
