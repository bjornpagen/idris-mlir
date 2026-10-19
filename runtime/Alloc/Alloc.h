// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::alloc: the runtime's memory, over snmalloc (Cells.cpp): raw blocks,
// cells, which it counts while they live, arrays, and GMP's allocation
// through it.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace rt::alloc {

// Whether this is the checked runtime, the archive libidris_rt_checked.a
// (IDRIS_RT_CHECKED, runtime/CMakeLists.txt), which a test links a program
// with to see what live cells cannot: a cell released once too often, and
// a reference to a cell after it died. There a heap cell that dies keeps
// its memory, which the allocator never gets back, and its header becomes
// `freed`, so that every later count operation on it meets the mark
// (rt::rc). The same sources build both runtimes; only this constant
// differs.
inline constexpr bool checked = IDRIS_RT_CHECKED != 0;

// The info of a heap cell that died in the checked runtime: a kind no cell
// is made with (the kinds are seven bits, and idris_rt.h's are the first
// few), and no object slot, so nothing that reads it as a cell walks on.
inline constexpr uint32_t freedInfo = idris_rt_info(0, 0, 0x7Fu);

// No heap address the allocator hands out has more bits than this: its
// pagemap covers no more (Cells.cpp checks snmalloc against it). The dying
// list of rt::rc keeps an address in that many bits.
inline constexpr unsigned heapAddressBits = 48;

// Exhausted memory is a crash: the allocator's, and any request for more
// than an integer can hold, which no allocation could meet.
[[noreturn]] void outOfMemory();

// Raw memory, which is not a cell: `size` bytes from snmalloc, or a crash
// when memory is exhausted. reallocate moves a block to `size` bytes, its
// contents kept up to the smaller size, and may keep it where it is.
void *allocate(size_t size);
void *reallocate(void *block, size_t size);
void release(void *block);

// A cell of `size` bytes with the header {1, info}, counted as live.
// Exhausted memory is a crash.
void *newCell(size_t size, uint32_t info);

// Frees the memory of a counted heap cell, and stops counting it.
void freeCell(void *cell);

// Stops counting a heap cell that became persistent: it lives until the
// program ends, as static data does, and is no live cell of the heap.
void forgetCell();

} // namespace rt::alloc
