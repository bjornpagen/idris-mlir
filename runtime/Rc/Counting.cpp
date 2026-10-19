// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The C ABI's reference counting, over rt::rc's inline counting. A
// saturated count is not counted, so an increment reaches UINT32_MAX at most
// and stays there.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Rc/Rc.h"
#include "idris_rt.h"

#include <stddef.h>

namespace {

[[noreturn]] void misused(const char *cause, size_t length) { idris_rt_crash(cause, length); }

} // namespace

namespace rt::rc {

// A cell that died is marked (rt::alloc::freedInfo) and kept, so a count
// operation on it is a release once too often or a reference that outlived
// its cell. A stack cell lies in the frame of the function that made it,
// and the stack grows down on every target, as the runner's guard below
// it says (Start/Runner.cpp): this function's own frame is below every
// frame that is live, so a stack cell below it is in a frame that has
// returned. One above it may be too, in memory a later call has taken
// again: that one is not seen.
[[gnu::noinline]] void checkLive(const idris_rt_header *cell) {
  if (cell->info == rt::alloc::freedInfo) [[unlikely]] {
    static constexpr char cause[] = "a count operation on a cell that died";
    misused(cause, sizeof cause - 1);
  }
  if (isStack(cell->info) && static_cast<const void *>(cell) < __builtin_frame_address(0))
      [[unlikely]] {
    static constexpr char cause[] = "a count operation on a cell of a frame that has returned";
    misused(cause, sizeof cause - 1);
  }
}

} // namespace rt::rc

// One more owned reference; a count that would reach UINT32_MAX saturates
// there.
extern "C" void idris_rt_inc(void *o) { rt::rc::inc(o); }

// One owned reference less. At 0 the object is released: a box's or a
// thunk's object slots lose a reference each, and then its memory is freed
// (a stack cell's is not). Objects that reach 0 in turn are released the
// same way, from a worklist that runs through the dying cells themselves:
// no recursion and no allocation, so freeing takes constant stack however
// deep the structure is.
extern "C" void idris_rt_dec(void *o) { rt::rc::dec(o); }

// Whether a cell is exclusive: count 1, and not a stack cell, so never a
// persistent one. It takes a cell, never a word that may be NULL or a small
// value: the caller knows which it holds, and a cell is what it asks about.
extern "C" bool idris_rt_is_unique(const idris_rt_header *cell) {
  return rt::rc::isExclusive(cell);
}

// Frees the memory of a counted heap cell, and nothing else: the caller has
// already moved out what it owns, having found it exclusive
// (idris_rt_is_unique), and reuses the memory of such a cell for one of the
// same size, rewriting the header, or frees it here. A stack cell's memory
// is its frame's, so a stack cell is left alone too.
extern "C" void idris_rt_free_cell(void *o) {
  if (!rt::rc::isObject(o))
    return;
  idris_rt_header *cell = rt::rc::headerOf(o);
  rt::rc::touch(cell);
  if (rt::rc::isCounted(cell->count) && !rt::rc::isStack(cell->info))
    rt::alloc::freeCell(cell);
}

// After a memo cell's force wrote its value: a persistent cell (static
// data, count 0) makes what it now holds persistent too, so that
// everything static data reaches is static; a counted cell holds its value
// counted, released when the cell dies. idr-lower calls it after every
// force, on the cell, which is a cell, never NULL or an odd word.
extern "C" void idris_rt_persist_held(void *o) {
  idris_rt_header *cell = rt::rc::headerOf(o);
  rt::rc::touch(cell);
  if (cell->count == 0) [[unlikely]]
    rt::rc::persistHeld(cell);
}
