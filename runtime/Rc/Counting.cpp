// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The C ABI's reference counting, over rt::rc's inline counting: one
// increment and one decrement per kind of word, of one word or of a run of
// slots, each testing exactly what its kind leaves open; the test of
// exclusivity; the two frees of a reuse token and the release of a cell
// proved dead, which read no count of the cell they are given. A
// saturated count is not counted, so an increment reaches UINT32_MAX at most
// and stays there.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "End/End.h"
#include "Rc/Rc.h"
#include "idris_rt.h"

#include <stdint.h>

namespace {

// A slot's word as counting reads it: a pointer as it is, a big's word as
// the address it may be.
const void *wordOf(const void *slot) { return slot; }
const void *wordOf(idris_rt_big slot) { return reinterpret_cast<const void *>(slot); }

// Each of `n` contiguous slots from `first`, one more or one less
// reference, as a cell's release walks them. The C ABI passes the first
// slot's address as a pointer to slots of the kind and the count as a
// 64-bit integer, never negative.
template <rt::rc::WordKind K, class Slot>
void incRun(const Slot *first, int64_t n) {
  for (int64_t i = 0; i < n; ++i)
    rt::rc::inc<K>(wordOf(first[i]));
}

template <rt::rc::WordKind K, class Slot>
void decRun(const Slot *first, int64_t n) {
  for (int64_t i = 0; i < n; ++i)
    rt::rc::dec<K>(wordOf(first[i]));
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
extern "C" void idris_rt_inc_cell(idris_rt_header *word) { rt::rc::inc<rt::rc::CellWord>(word); }
extern "C" void idris_rt_dec_cell(idris_rt_header *word) { rt::rc::dec<rt::rc::CellWord>(word); }
extern "C" void idris_rt_inc_maybe_cell(idris_rt_header *word) {
  rt::rc::inc<rt::rc::MaybeCellWord>(word);
}
extern "C" void idris_rt_dec_maybe_cell(idris_rt_header *word) {
  rt::rc::dec<rt::rc::MaybeCellWord>(word);
}
extern "C" void idris_rt_inc_big(idris_rt_big word) { rt::rc::inc<rt::rc::BigWord>(wordOf(word)); }
extern "C" void idris_rt_dec_big(idris_rt_big word) { rt::rc::dec<rt::rc::BigWord>(wordOf(word)); }
extern "C" void idris_rt_inc_any(void *word) { rt::rc::inc<rt::rc::AnyWord>(word); }
extern "C" void idris_rt_dec_any(void *word) { rt::rc::dec<rt::rc::AnyWord>(word); }

// The same, for each of `n` contiguous slots of one kind: a cell taken
// apart counts the slots that move, or that die, in one call.
extern "C" void idris_rt_inc_run_cell(idris_rt_header *const *first, int64_t n) {
  incRun<rt::rc::CellWord>(first, n);
}
extern "C" void idris_rt_dec_run_cell(idris_rt_header *const *first, int64_t n) {
  decRun<rt::rc::CellWord>(first, n);
}
extern "C" void idris_rt_inc_run_maybe_cell(idris_rt_header *const *first, int64_t n) {
  incRun<rt::rc::MaybeCellWord>(first, n);
}
extern "C" void idris_rt_dec_run_maybe_cell(idris_rt_header *const *first, int64_t n) {
  decRun<rt::rc::MaybeCellWord>(first, n);
}
extern "C" void idris_rt_inc_run_big(const idris_rt_big *first, int64_t n) {
  incRun<rt::rc::BigWord>(first, n);
}
extern "C" void idris_rt_dec_run_big(const idris_rt_big *first, int64_t n) {
  decRun<rt::rc::BigWord>(first, n);
}
extern "C" void idris_rt_inc_run_any(void *const *first, int64_t n) {
  incRun<rt::rc::AnyWord>(first, n);
}
extern "C" void idris_rt_dec_run_any(void *const *first, int64_t n) {
  decRun<rt::rc::AnyWord>(first, n);
}

// Whether a counted cell holds the only reference to itself: its count is
// 1. A static cell (0) and a saturated one are never exclusive. Asked only
// of a value exclusivity proved nothing of; a value proved exclusive asks
// nothing.
extern "C" bool idris_rt_is_unique(const idris_rt_header *cell) {
  return rt::rc::isExclusive(cell);
}

// Frees the memory of a reuse token whose cell was found or proved
// exclusive, its fields moved out: the caller reuses such a cell's memory
// for one of its size, rewriting the header, or frees it here. One proved
// exclusive is a cell, so nothing is read; one that may be null, from a
// take of a cell exclusivity proved nothing of, tests that alone.
extern "C" void idris_rt_free_token(idris_rt_header *cell) {
  rt::rc::touch(cell);
  rt::alloc::freeCell(cell);
}

extern "C" void idris_rt_free_maybe_token(idris_rt_header *cell) {
  if (cell == nullptr)
    return;
  rt::rc::touch(cell);
  rt::alloc::freeCell(cell);
}

// Releases a cell the compiler proved dead, and every cell that dies in
// turn, and frees them: a held buffer whose storage its owner's claim
// covers dies with the owner, so its count says nothing the compiler does
// not know and is never read. Its elements may be shared, so each loses a
// reference as a dying cell's slots do. The checked runtime confirms the
// cell is live first, as for a token, which costs the shipped one nothing.
extern "C" void idris_rt_release_dead(idris_rt_header *cell) {
  rt::rc::touch(cell);
  rt::rc::release(cell);
}
