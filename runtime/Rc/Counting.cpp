// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The C ABI's reference counting, over rt::rc's inline counting: one
// increment and one decrement per kind of word, of one word or of a run of
// slots, each testing exactly what its kind leaves open; the test of
// exclusivity; and the two frees of a reuse token, which read no count. A
// saturated count is not counted, so an increment reaches UINT32_MAX at most
// and stays there.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "End/End.h"
#include "Rc/Rc.h"
#include "idris_rt.h"

#include <stdint.h>

namespace {

// Each of `n` contiguous slots from `first`, one more or one less
// reference, as a cell's release walks them. The C ABI passes the first
// slot's address as a pointer and the count as a 64-bit integer, never
// negative.
template <rt::rc::WordKind K>
void incRun(void *first, int64_t n) {
  auto *const *slots = static_cast<void *const *>(first);
  for (int64_t i = 0; i < n; ++i)
    rt::rc::inc<K>(slots[i]);
}

template <rt::rc::WordKind K>
void decRun(void *first, int64_t n) {
  auto *const *slots = static_cast<void *const *>(first);
  for (int64_t i = 0; i < n; ++i)
    rt::rc::dec<K>(slots[i]);
}

} // namespace

namespace rt::rc {

// A cell that died is marked (rt::alloc::freedInfo) and kept, so a count
// operation on it is a release once too often or a reference that outlived
// its cell: the runtime's internal error, of the program as the compiler
// counted it.
[[gnu::noinline]] void checkLive(const idris_rt_header *cell) {
  if (cell->info == rt::alloc::freedInfo) [[unlikely]]
    rt::end::end(rt::end::CountOfDeadCell{});
}

} // namespace rt::rc

// One more owned reference, and one less, at 0 releasing the cell: its
// object slots lose a reference each, then its memory is freed, and cells
// that reach 0 in turn are released the same way, from a worklist that runs
// through the dying cells themselves, so freeing takes constant stack
// however deep the structure is. A word's kind is its type's: a cell; a cell
// or NULL; a cell or a small value; or any of the three.
extern "C" void idris_rt_inc_cell(void *word) { rt::rc::inc<rt::rc::CellWord>(word); }
extern "C" void idris_rt_dec_cell(void *word) { rt::rc::dec<rt::rc::CellWord>(word); }
extern "C" void idris_rt_inc_maybe_cell(void *word) { rt::rc::inc<rt::rc::MaybeCellWord>(word); }
extern "C" void idris_rt_dec_maybe_cell(void *word) { rt::rc::dec<rt::rc::MaybeCellWord>(word); }
extern "C" void idris_rt_inc_big(idris_rt_big word) {
  rt::rc::inc<rt::rc::BigWord>(reinterpret_cast<const void *>(word));
}
extern "C" void idris_rt_dec_big(idris_rt_big word) {
  rt::rc::dec<rt::rc::BigWord>(reinterpret_cast<const void *>(word));
}
extern "C" void idris_rt_inc_any(void *word) { rt::rc::inc<rt::rc::AnyWord>(word); }
extern "C" void idris_rt_dec_any(void *word) { rt::rc::dec<rt::rc::AnyWord>(word); }

// The same, for each of `n` contiguous slots of one kind: a cell taken
// apart counts the slots that move, or that die, in one call.
extern "C" void idris_rt_inc_run_cell(void *first, int64_t n) {
  incRun<rt::rc::CellWord>(first, n);
}
extern "C" void idris_rt_dec_run_cell(void *first, int64_t n) {
  decRun<rt::rc::CellWord>(first, n);
}
extern "C" void idris_rt_inc_run_maybe_cell(void *first, int64_t n) {
  incRun<rt::rc::MaybeCellWord>(first, n);
}
extern "C" void idris_rt_dec_run_maybe_cell(void *first, int64_t n) {
  decRun<rt::rc::MaybeCellWord>(first, n);
}
extern "C" void idris_rt_inc_run_big(void *first, int64_t n) {
  incRun<rt::rc::BigWord>(first, n);
}
extern "C" void idris_rt_dec_run_big(void *first, int64_t n) {
  decRun<rt::rc::BigWord>(first, n);
}
extern "C" void idris_rt_inc_run_any(void *first, int64_t n) {
  incRun<rt::rc::AnyWord>(first, n);
}
extern "C" void idris_rt_dec_run_any(void *first, int64_t n) {
  decRun<rt::rc::AnyWord>(first, n);
}

// Whether a counted cell holds the only reference to itself: its count is
// 1. A static cell (0) and a saturated one are never exclusive. Asked only
// of a value exclusivity proved nothing of; a value proved exclusive asks
// nothing.
extern "C" bool idris_rt_is_unique(void *cell) {
  return rt::rc::isExclusive(rt::rc::headerOf(cell));
}

// Frees the memory of a reuse token whose cell was found or proved
// exclusive, its fields moved out: the caller reuses such a cell's memory
// for one of its size, rewriting the header, or frees it here. One proved
// exclusive is a cell, so nothing is read; one that may be null, from a
// take of a cell exclusivity proved nothing of, tests that alone.
extern "C" void idris_rt_free_token(void *cell) {
  rt::rc::touch(rt::rc::headerOf(cell));
  rt::alloc::freeCell(cell);
}

extern "C" void idris_rt_free_maybe_token(void *cell) {
  if (cell == nullptr)
    return;
  rt::rc::touch(rt::rc::headerOf(cell));
  rt::alloc::freeCell(cell);
}
