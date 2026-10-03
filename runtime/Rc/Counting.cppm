// rt.rc:counting: the C ABI's reference counting. A saturated count is not
// counted, so an increment reaches UINT32_MAX at most and stays there.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

export module rt.rc:counting;

import rt.alloc;
import :freeing;
import :objects;

extern "C" void idris_rt_inc(void *o) {
  if (!rt::rc::isObject(o))
    return;
  idris_rt_header *cell = rt::rc::headerOf(o);
  if (rt::rc::isCounted(cell->count))
    ++cell->count;
}

extern "C" void idris_rt_dec(void *o) {
  if (idris_rt_header *dead = rt::rc::lastReference(o))
    rt::rc::release(dead);
}

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
