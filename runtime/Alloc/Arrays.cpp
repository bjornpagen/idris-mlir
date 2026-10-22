// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Array cells, the memory behind every memref (idris_rt_array): a cell with
// every object slot NULL, and the counted copy between two views of cells.
// The compiler reads and writes elements itself, through a memref's
// descriptor, with the layout it chose; the runtime allocates the cell,
// copies where a copy must count or stride, and frees the cell (rt::rc).
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "End/End.h"
#include "Rc/Rc.h"
#include "idris_rt.h"

#include "idr/IR/Generated/RuntimeLayout.h.inc"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

// The descriptor is the prefix of the struct LLVM gives a ranked memref
// descriptor on every target: two pointers and an offset, one word each.
static_assert(sizeof(idris_rt_memref) == 3 * IDRIS_RT_WORD_BYTES);
static_assert(offsetof(idris_rt_memref, aligned) == IDRIS_RT_WORD_BYTES);
static_assert(offsetof(idris_rt_memref, offset) == 2 * IDRIS_RT_WORD_BYTES);

// The compiler lays an array cell out by the specification's count of its
// header bytes, never by this struct's size on the build machine: the two
// are one.
static_assert(sizeof(idris_rt_array) == idr::runtime::arrayHeaderBytes,
              "an array cell's header is the specification's");

namespace {

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
    rt::rc::inc<rt::rc::AnyWord>(held[i]);
    rt::rc::dec<rt::rc::AnyWord>(old[i]);
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

// Copies one row, the last dimension, from the element at `from` to the
// one at `to`: its bytes at once when they are plain and lie together on
// both sides, else element by element.
void copyRow(const Walk &walk, char *to, const char *from) {
  size_t last = walk.rank - 1;
  int64_t size = walk.sizes[last];
  ptrdiff_t bytes = walk.element.bytes;
  ptrdiff_t fromStep = static_cast<ptrdiff_t>(walk.fromStrides[last]) * bytes;
  ptrdiff_t toStep = static_cast<ptrdiff_t>(walk.toStrides[last]) * bytes;
  if (walk.element.objs == 0 && fromStep == bytes && toStep == bytes) {
    memmove(to, from, static_cast<size_t>(size * bytes));
    return;
  }
  for (int64_t i = 0; i < size; ++i, to += toStep, from += fromStep)
    assign(to, from, walk.element);
}

// Copies every row, in row-major order: row r's place in each outer
// dimension is r's digit in the mixed radix of their sizes, taken from the
// innermost out, so the walk keeps no counter per dimension and recurses on
// nothing. A dimension of size 0 copies nothing.
void copyAll(const Walk &walk, char *to, const char *from) {
  if (walk.rank == 0) {
    assign(to, from, walk.element);
    return;
  }
  size_t outer = walk.rank - 1;
  uint64_t rows = 1;
  for (size_t d = 0; d < outer; ++d)
    rows *= static_cast<uint64_t>(walk.sizes[d]);
  ptrdiff_t bytes = walk.element.bytes;
  for (uint64_t r = 0; r < rows; ++r) {
    ptrdiff_t fromOffset = 0, toOffset = 0;
    uint64_t rest = r;
    for (size_t d = outer; d-- > 0;) {
      auto size = static_cast<uint64_t>(walk.sizes[d]);
      auto at = static_cast<ptrdiff_t>(rest % size);
      rest /= size;
      fromOffset += at * static_cast<ptrdiff_t>(walk.fromStrides[d]) * bytes;
      toOffset += at * static_cast<ptrdiff_t>(walk.toStrides[d]) * bytes;
    }
    copyRow(walk, to + toOffset, from + fromOffset);
  }
}

// A view's first element.
char *firstOf(const idris_rt_memref *view, ptrdiff_t bytes) {
  return view->aligned + static_cast<ptrdiff_t>(view->offset) * bytes;
}

} // namespace

// A new array cell of `count` elements with the header `info` (kind
// IDRIS_RT_KIND_ARRAY). When its elements hold objects, every byte of them
// is 0, so every object slot is NULL until a store: a store releases what
// the slot held, and the cell's death releases every slot, written or not;
// otherwise they are not written. The first element is aligned to
// IDRIS_RT_WORD_BYTES. A count whose cell no address space holds is as
// much memory as the machine has not: the process's out-of-memory ending.
extern "C" void *idris_rt_array_new(int64_t elements, int32_t word) {
  auto count = static_cast<uint64_t>(elements);
  auto info = static_cast<uint32_t>(word);
  uint64_t stride = idris_rt_info_tag(info);
  size_t bytes = 0;
  if (__builtin_mul_overflow(count, stride, &bytes) ||
      __builtin_add_overflow(bytes, sizeof(idris_rt_array), &bytes))
    rt::end::end(rt::end::OutOfMemory{});
  auto *array = static_cast<idris_rt_array *>(idris_rt_info_objs(info) != 0
                                                  ? rt::alloc::newZeroedCell(bytes, info)
                                                  : rt::alloc::newCell(bytes, info));
  array->length = count;
  return array;
}

// memref.copy, where idr-lower does not copy the bytes itself: each element
// of the view `from` assigned to the same place of the view `to`, in
// row-major order. Both have rank `rank` and from's sizes. The element is
// the one to's cell describes, and from's cell holds the same: each object
// slot copied gains one reference, then the slot it overwrites loses one,
// then the element's bytes are moved. So a cell fresh from
// idris_rt_array_new may be the target as it is, and a view copied onto
// itself, the one overlap allowed, is left as it was.
extern "C" void idris_rt_memref_copy(int64_t rank, void *source, void *target) {
  const auto *from = static_cast<const idris_rt_memref *>(source);
  const auto *to = static_cast<const idris_rt_memref *>(target);
  uint32_t info = to->allocated->header.info;
  Element element{static_cast<ptrdiff_t>(idris_rt_info_tag(info)), idris_rt_info_objs(info)};
  auto dims = static_cast<size_t>(rank);
  const int64_t *sizes = shapeOf(from);
  Walk walk{sizes, sizes + dims, shapeOf(to) + dims, dims, element};
  copyAll(walk, firstOf(to, element.bytes), firstOf(from, element.bytes));
}
