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
#pragma once

#include "Alloc/Alloc.h"
#include "idris_rt.h"

#include <concepts>
#include <stdint.h>

namespace rt::rc {

inline constexpr uint32_t saturated = UINT32_MAX;

// The checked runtime's test of a cell a count operation is about to touch
// (rt::alloc::checked): a heap cell that died ends the program, as the
// runtime's internal error. Out of line: it is never on a shipped path.
void checkLive(const idris_rt_header *cell);

// Every count operation's cell passes here first: nothing in the runtime
// as it is built for programs, the test in the checked one.
inline void touch(const idris_rt_header *cell) {
  if constexpr (rt::alloc::checked)
    checkLive(cell);
}

// What a word that holds a counted reference may be besides a cell, two
// facts its type fixes when the lowering picks the entry that counts it:
// NULL (an unused slot of an unboxed sum), and a small value (a big's odd
// word). Their four products are the kinds' lattice: a cell below a
// cell-or-NULL and a big, and their join, any word.
enum class Null : uint8_t { Never, Maybe };
enum class Small : uint8_t { Never, Maybe };

template <Null N, Small S>
struct Kind {
  static constexpr Null null = N;
  static constexpr Small small = S;
};

template <class K>
concept WordKind = requires {
  { K::null } -> std::convertible_to<Null>;
  { K::small } -> std::convertible_to<Small>;
};

using CellWord = Kind<Null::Never, Small::Never>;
using MaybeCellWord = Kind<Null::Maybe, Small::Never>;
using BigWord = Kind<Null::Never, Small::Maybe>;
using AnyWord = Kind<Null::Maybe, Small::Maybe>;

// Whether a word of the kind holds a cell: exactly what the kind leaves
// open is tested, so a cell's word tests nothing.
template <WordKind K>
[[gnu::always_inline]] inline bool holdsCell(const void *o) {
  auto word = reinterpret_cast<uintptr_t>(o);
  if constexpr (K::null == Null::Maybe && K::small == Small::Maybe)
    return word != 0 && !idris_rt_word_is_small(static_cast<idris_rt_big>(word));
  else if constexpr (K::null == Null::Maybe)
    return word != 0;
  else if constexpr (K::small == Small::Maybe)
    return !idris_rt_word_is_small(static_cast<idris_rt_big>(word));
  else
    return true;
}

inline idris_rt_header *headerOf(void *o) { return static_cast<idris_rt_header *>(o); }

// Neither static (0) nor saturated: one unsigned comparison for both, so
// keeping a saturated count is what leaves static data alone, and a value
// that only a function receiving both counted and static data meets, past
// the specialization by hold, costs no test more.
inline bool isCounted(uint32_t count) { return count - 1 < saturated - 1; }

// A counted cell that holds the only reference to itself.
inline bool isExclusive(const idris_rt_header *cell) {
  touch(cell);
  return cell->count == 1;
}

// Drops one reference to o, a slot whose kind the runtime does not know
// (a dying cell's), and returns o's cell when that was the last.
inline idris_rt_header *lastReference(void *o) {
  if (!holdsCell<AnyWord>(o))
    return nullptr;
  idris_rt_header *cell = headerOf(o);
  touch(cell);
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

// One reference more or less to a cell, which the caller holds as one. They
// hold strings and bigs as pointers to const: the count is the one field a
// reference may change, and only here. Static data is never written, so it
// may be read-only.
inline void incCell(const void *o) {
  idris_rt_header *cell = headerOf(const_cast<void *>(o));
  touch(cell);
  if (isCounted(cell->count))
    ++cell->count;
}

inline void decCell(const void *o) {
  idris_rt_header *cell = headerOf(const_cast<void *>(o));
  touch(cell);
  uint32_t count = cell->count;
  if (!isCounted(count))
    return;
  if (count == 1)
    release(cell);
  else
    cell->count = count - 1;
}

// One reference more or less to a word of the kind.
template <WordKind K>
inline void inc(const void *o) {
  if (holdsCell<K>(o))
    incCell(o);
}

template <WordKind K>
inline void dec(const void *o) {
  if (holdsCell<K>(o))
    decCell(o);
}

} // namespace rt::rc
