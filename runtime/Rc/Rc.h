// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::rc: reference counting over the header's count, and freeing. An
// object that dies releases its references from a worklist threaded through
// the dying cells themselves, as Lean's runtime frees (lean_del_core), so
// freeing a structure of any depth takes no recursion, no allocation and
// constant stack.
//
// What a word and a cell's header say to counting, and dropping one
// reference, are inline here: the decrement inlines into every caller.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "idris_rt.h"

#include <stdint.h>

namespace rt::rc {

inline constexpr uint32_t saturated = UINT32_MAX;

// A pointer to an object, and not NULL or an odd word (a small big).
inline bool isObject(const void *o) {
  auto word = reinterpret_cast<uintptr_t>(o);
  return word != 0 && (word & 1) == 0;
}

inline idris_rt_header *headerOf(void *o) { return static_cast<idris_rt_header *>(o); }

// Neither persistent (0) nor saturated.
inline bool isCounted(uint32_t count) { return count - 1 < saturated - 1; }

inline bool isStack(uint32_t info) { return (info & IDRIS_RT_STACK_CELL) != 0; }

// A cell whose fields may move out of it, and whose memory may be reused.
inline bool isExclusive(const idris_rt_header *cell) {
  return cell->count == 1 && !isStack(cell->info);
}

// Drops one reference to o, and returns o's cell when that was the last.
inline idris_rt_header *lastReference(void *o) {
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

// Releases a dead cell's references, and those of every cell that dies in
// turn, and frees them (Freeing.cpp).
void release(idris_rt_header *cell);

// What a persistent cell holds, released without freeing the cell: its
// memory is the program's, and its header stays.
void releaseHeld(idris_rt_header *cell);

} // namespace rt::rc
