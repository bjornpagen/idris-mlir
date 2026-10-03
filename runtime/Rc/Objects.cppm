// rt.rc:objects: what a word and a cell's header say to counting, and
// dropping one reference.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>

export module rt.rc:objects;

namespace rt::rc {

inline constexpr uint32_t saturated = UINT32_MAX;

// A pointer to an object, and not NULL or an odd word (a small big).
bool isObject(const void *o) {
  auto word = reinterpret_cast<uintptr_t>(o);
  return word != 0 && (word & 1) == 0;
}

idris_rt_header *headerOf(void *o) { return static_cast<idris_rt_header *>(o); }

// Neither persistent (0) nor saturated.
bool isCounted(uint32_t count) { return count - 1 < saturated - 1; }

bool isStack(uint32_t info) { return (info & IDRIS_RT_STACK_CELL) != 0; }

// A cell whose fields may move out of it, and whose memory may be reused.
bool isExclusive(const idris_rt_header *cell) {
  return cell->count == 1 && !isStack(cell->info);
}

// Drops one reference to o, and returns o's cell when that was the last.
idris_rt_header *lastReference(void *o) {
  if (!isObject(o))
    return nullptr;
  idris_rt_header *cell = headerOf(o);
  uint32_t count = cell->count;
  if (!isCounted(count))
    return nullptr;
  if (count == 1)
    return cell;
  cell->count = count - 1;
  return nullptr;
}

} // namespace rt::rc
