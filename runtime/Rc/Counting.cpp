// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The C ABI's reference counting, over rt::rc's inline counting. A
// saturated count is not counted, so an increment reaches UINT32_MAX at most
// and stays there.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Rc/Rc.h"
#include "idris_rt.h"

extern "C" void idris_rt_inc(void *o) { rt::rc::inc(o); }

extern "C" void idris_rt_dec(void *o) { rt::rc::dec(o); }

extern "C" bool idris_rt_is_unique(const void *o) {
  return rt::rc::isObject(o) && rt::rc::isExclusive(static_cast<const idris_rt_header *>(o));
}

extern "C" void idris_rt_free_cell(void *o) {
  if (!rt::rc::isObject(o))
    return;
  idris_rt_header *cell = rt::rc::headerOf(o);
  if (rt::rc::isCounted(cell->count) && !rt::rc::isStack(cell->info))
    rt::alloc::freeCell(cell);
}

// Only a persistent cell: a counted one releases what it holds when it dies.
extern "C" void idris_rt_caf_release(void *o) {
  if (!rt::rc::isObject(o))
    return;
  idris_rt_header *cell = rt::rc::headerOf(o);
  if (cell->count == 0)
    rt::rc::releaseHeld(cell);
}
