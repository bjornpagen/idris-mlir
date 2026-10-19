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
  return word != 0 && !idris_rt_word_is_small(static_cast<idris_rt_big>(word));
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

// One reference more or less to a cell, which the caller holds as one: a
// pointer to a header, never NULL or an odd word (a string, a large big, a
// handle's string). They hold strings and bigs as pointers to const: the
// count is the one field a reference may change, and only here. A
// persistent cell is never written, so it may be read-only.
inline void incCell(const void *o) {
  idris_rt_header *cell = headerOf(const_cast<void *>(o));
  if (isCounted(cell->count))
    ++cell->count;
}

inline void decCell(const void *o) {
  idris_rt_header *cell = headerOf(const_cast<void *>(o));
  uint32_t count = cell->count;
  if (!isCounted(count))
    return;
  if (count == 1)
    release(cell);
  else
    cell->count = count - 1;
}

// idris_rt_inc and idris_rt_dec, inline: a word in an object slot may be
// NULL or an odd word too, which counting leaves alone.
inline void inc(const void *o) {
  if (isObject(o))
    incCell(o);
}

inline void dec(const void *o) {
  if (isObject(o))
    decCell(o);
}

// What a persistent cell holds, made persistent: every counted cell it
// reaches, through object slots, gets count 0 and is no longer a live cell
// of the heap; a persistent cell ends the walk. A static memo cell's force
// writes a counted value into static data, which then holds it until the
// program ends: everything static data reaches is static.
void persistHeld(idris_rt_header *cell);

} // namespace rt::rc
