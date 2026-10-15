// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Array cells, the memory behind every memref (idris_rt_array): a cell with
// every object slot NULL, and the counted copy between two views of cells.
// The compiler reads and writes elements itself, through a memref's
// descriptor, with the layout it chose; the runtime allocates the cell,
// copies where a copy must count or stride, and frees the cell (rt::rc).
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

// The descriptor is the prefix of the struct LLVM gives a ranked memref
// descriptor on every target: two pointers and an offset, one word each.
static_assert(sizeof(idris_rt_memref) == 3 * IDRIS_RT_WORD_BYTES);
static_assert(offsetof(idris_rt_memref, aligned) == IDRIS_RT_WORD_BYTES);
static_assert(offsetof(idris_rt_memref, offset) == 2 * IDRIS_RT_WORD_BYTES);

namespace {

[[noreturn]] void tooLarge() {
  static constexpr char message[] = "idris runtime: array too large\n";
  idris_rt_crash(message, sizeof message - 1);
}

// A descriptor's sizes, then its strides, right after its three words.
const int64_t *shapeOf(const idris_rt_memref *view) {
  return reinterpret_cast<const int64_t *>(view + 1);
}

// What a copy reads of the element, from the target's cell.
struct Element {
  ptrdiff_t bytes;
  uint32_t objs;
};

// One element assigned: each object slot it copies gains a reference before
// the slot it overwrites loses one, so a slot both hold keeps its count; then
// the bytes. A view copied onto itself is the one overlap a copy meets.
void assign(char *to, const char *from, Element element) {
  void *const *held = static_cast<void *const *>(static_cast<const void *>(from));
  void **old = static_cast<void **>(static_cast<void *>(to));
  for (uint32_t i = 0; i < element.objs; ++i) {
    idris_rt_inc(held[i]);
    idris_rt_dec(old[i]);
  }
  memmove(to, from, static_cast<size_t>(element.bytes));
}

// The two views of a copy, dimension by dimension.
struct Walk {
  const int64_t *sizes;
  const int64_t *fromStrides;
  const int64_t *toStrides;
  size_t rank;
  Element element;
};

// Copies dimension `dim` and those inside it, from the element at `from` to
// the one at `to`. The last level is a row: its bytes at once when they are
// plain and lie together on both sides, else element by element. A level of
// size 0 copies nothing.
void copyFrom(const Walk &walk, size_t dim, char *to, const char *from) {
  if (dim == walk.rank) {
    assign(to, from, walk.element);
    return;
  }
  int64_t size = walk.sizes[dim];
  ptrdiff_t bytes = walk.element.bytes;
  ptrdiff_t fromStep = static_cast<ptrdiff_t>(walk.fromStrides[dim]) * bytes;
  ptrdiff_t toStep = static_cast<ptrdiff_t>(walk.toStrides[dim]) * bytes;
  if (dim + 1 == walk.rank && walk.element.objs == 0 && fromStep == bytes && toStep == bytes) {
    memmove(to, from, static_cast<size_t>(size * bytes));
    return;
  }
  for (int64_t i = 0; i < size; ++i, to += toStep, from += fromStep)
    copyFrom(walk, dim + 1, to, from);
}

// A view's first element.
char *firstOf(const idris_rt_memref *view, ptrdiff_t bytes) {
  return view->aligned + static_cast<ptrdiff_t>(view->offset) * bytes;
}

} // namespace

extern "C" idris_rt_array *idris_rt_array_new(uint64_t count, uint32_t info) {
  uint64_t stride = idris_rt_info_tag(info);
  // The cell's size must fit a size_t with the header and length before it.
  if (stride != 0 && count > (SIZE_MAX - sizeof(idris_rt_array)) / stride)
    tooLarge();
  auto bytes = static_cast<size_t>(count * stride);
  auto *array =
      static_cast<idris_rt_array *>(rt::alloc::newCell(sizeof(idris_rt_array) + bytes, info));
  array->length = count;
  // Every object slot is NULL until a store: a store releases what the slot
  // held, and the cell's death releases every slot, written or not.
  if (idris_rt_info_objs(info) != 0)
    memset(array + 1, 0, bytes);
  return array;
}

extern "C" void idris_rt_memref_copy(int64_t rank, const idris_rt_memref *from,
                                     const idris_rt_memref *to) {
  uint32_t info = to->allocated->header.info;
  Element element{static_cast<ptrdiff_t>(idris_rt_info_tag(info)), idris_rt_info_objs(info)};
  auto dims = static_cast<size_t>(rank);
  const int64_t *sizes = shapeOf(from);
  Walk walk{sizes, sizes + dims, shapeOf(to) + dims, dims, element};
  copyFrom(walk, 0, firstOf(to, element.bytes), firstOf(from, element.bytes));
}
