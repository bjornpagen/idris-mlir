// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::alloc: the runtime's memory, over snmalloc (Cells.cpp): the heap's
// span, set up once by the runner; raw blocks; cells; arrays; and GMP's
// allocation through it. No allocation returns a failure: running out of
// memory is the process's out-of-memory ending, wherever it is met.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace rt::alloc {

// Whether this is the checked runtime, the archive libidris_rt_checked.a
// (IDRIS_RT_CHECKED, runtime/CMakeLists.txt), which a test links a program
// with to see what the shipped runtime cannot: a cell released once too
// often, a reference to a cell after it died, and cells still live when
// main returns. There a heap cell that dies keeps its memory, which the
// allocator never gets back, and its header becomes `freed`, so that every
// later count operation on it meets the mark (rt::rc); and the cells the
// program holds are counted. The same sources build both runtimes; only
// this constant differs, and the shipped one holds no count.
inline constexpr bool checked = IDRIS_RT_CHECKED != 0;

// The info of a heap cell that died in the checked runtime: a kind no cell
// is made with, and no object slot, so nothing that reads it as a cell
// walks on.
inline constexpr uint32_t freedInfo = idris_rt_info(0, 0, 0xFFu);

// No heap address the allocator hands out has more bits than this: the
// heap's span lies in user space, which no target maps past it. The dying
// list of rt::rc keeps an address in that many bits.
inline constexpr unsigned heapAddressBits = 48;

// Sets the heap up, once, before anything allocates: the span its chunks
// are reserved from, from an address aligned to the region Apple's
// prefetcher reads; the page map over that span, reserved and committed a
// page at a time as chunks come; snmalloc's state; and the host's limit on
// committed memory (`limit`, SIZE_MAX for none), which an allocation past
// it meets as out of memory. False when the system refuses the page map's
// address space, which is the process running out of memory.
bool initialise(size_t limit) noexcept;

// `size` bytes of address space, whole pages, from the span's start, before
// any chunk: the runner's stacks, which so lie in the heap's first region.
// Null when the system refuses them.
char *reserveFirst(size_t size) noexcept;

// Raw memory, which is not a cell: `size` bytes, or the out-of-memory
// ending. reallocate moves a block to `size` bytes, its contents kept up to
// the smaller size, and keeps it where it is when its size class holds it.
void *allocate(size_t size);
void *reallocate(void *block, size_t size);

// The bytes an allocation of `size` takes, its size class's: a block of
// exactly that many ends where its class does, so bytesToEnd finds its end
// from any byte of it.
size_t classSize(size_t size);

// The bytes from `inside`, a byte of a block, to the block's end: what a
// chunk's trailer is found by, whatever its bytes hold.
size_t bytesToEnd(const void *inside);
void release(void *block);

// A cell of `size` bytes with the header {1, info}; zeroed past the header
// when its slots must read as NULL before anything is stored in them.
void *newCell(size_t size, uint32_t info);
void *newZeroedCell(size_t size, uint32_t info);

// Frees the memory of a counted heap cell.
void freeCell(void *cell);

// The heap cells the checked runtime allocated and has not freed, which a
// program case reads when main returns: the shipped runtime reads and
// writes it nowhere, so no shipped program holds it (check-archive.sh). The
// program is single-threaded.
inline uint64_t cellsHeld = 0;

} // namespace rt::alloc
