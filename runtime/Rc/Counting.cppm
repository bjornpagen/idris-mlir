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

namespace {

// Persistent suspensions that have stored a value. The nodes are raw
// blocks, not cells. main's return walks the list and drops what they own.
struct Kept {
  idris_rt_header *cell;
  Kept *next;
};

Kept *kept = nullptr;

} // namespace

extern "C" void idris_rt_lazy_kept(void *o) {
  if (rt::alloc::arenaActive || !rt::rc::isObject(o))
    return;
  idris_rt_header *cell = rt::rc::headerOf(o);
  if (rt::rc::isCounted(cell->count) || rt::rc::isStack(cell->info))
    return;
  auto *node = static_cast<Kept *>(rt::alloc::allocate(sizeof(Kept)));
  node->cell = cell;
  node->next = kept;
  kept = node;
}

extern "C" void idris_rt_release_persistent(void) {
  while (kept != nullptr) {
    Kept *node = kept;
    kept = node->next;
    rt::rc::releaseKept(node->cell);
    rt::alloc::release(node);
  }
}
