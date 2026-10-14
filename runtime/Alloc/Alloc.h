// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::alloc: the runtime's memory: raw blocks, cells, which it counts while
// they live, the allocation entry points over snmalloc, arrays, and GMP's
// allocation through it.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace rt::alloc {

// No heap address the allocator hands out has more bits than this: its
// pagemap covers no more (Classes.cpp checks snmalloc against it). The dying
// list of rt::rc keeps an address in that many bits.
inline constexpr unsigned heapAddressBits = 48;

// Exhausted memory is a crash: the allocator's, and any request for more
// than an integer can hold, which no allocation could meet.
[[noreturn]] void outOfMemory();

// Raw memory, which is not a cell: `size` bytes from snmalloc, or a crash
// when memory is exhausted.
void *allocate(size_t size);
void release(void *block);

// A cell of `size` bytes with the header {1, info}, counted as live.
// Exhausted memory is a crash.
void *newCell(size_t size, uint32_t info);

// Frees the memory of a counted heap cell, and stops counting it.
void freeCell(void *cell);

// Makes GMP allocate through the runtime (idris_rt_gmp_init), once.
void gmpReady();

} // namespace rt::alloc
