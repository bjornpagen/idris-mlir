// rt.rc:freeing: releasing a dead cell's references and freeing it, through
// the dying list.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

export module rt.rc:freeing;

import rt.alloc;
import :objects;

namespace {

// The bits of a stack address: the target entry's (CMakeLists.txt), which
// states them after checking its address space; no target inherits
// another's.
#ifndef IDRIS_RT_STACK_ADDRESS_BITS
#error "the dying list keeps a stack cell's address: the target entry states its bits"
#endif
constexpr unsigned stackAddressBits = IDRIS_RT_STACK_ADDRESS_BITS;

// The count holds the low 32 bits of the next cell's address, and the tag
// field of info its high bits; objs, kind and the stack bit stay. An array
// whose elements hold objects keeps its tag, the element size its release
// steps by, and its length holds the high bits instead (steppedLength). The
// tag field is the header's (IDRIS_RT_TAG_LIMIT), not a second width.
constexpr unsigned addressLowBits = 32;
constexpr unsigned addressHighBits = 16;
static_assert(IDRIS_RT_TAG_LIMIT == (1u << addressHighBits));
constexpr uint32_t tagField = IDRIS_RT_TAG_LIMIT - 1u;
constexpr unsigned lengthBits = 64 - addressHighBits;
constexpr uint64_t lengthField = (uint64_t{1} << lengthBits) - 1u;

// The length of an array whose elements hold objects, or null. Each element
// is then at least a word and the array lies in the address space, so the
// top addressHighBits bits of its length are 0 while it lives.
uint64_t *steppedLength(idris_rt_header *cell) {
  if (idris_rt_info_kind(cell->info) != IDRIS_RT_KIND_ARRAY || idris_rt_info_objs(cell->info) == 0)
    return nullptr;
  return &reinterpret_cast<idris_rt_array *>(cell)->length;
}

// The cells whose count reached 0 and whose references are still to be
// released: a stack threaded through the cells. A dying cell's count is
// dead, and so is its tag, or for an array whose elements hold objects the
// top of its length: addressLowBits + addressHighBits bits, which hold the
// next cell's address. A heap cell's has no more bits than the allocator's
// pagemap covers (rt.alloc), and a stack cell's no more than the target's
// stacks (above).
class Dying {
  static_assert(rt::alloc::heapAddressBits <= addressLowBits + addressHighBits,
                "a heap address fits a count and a tag");
  static_assert(stackAddressBits <= addressLowBits + addressHighBits,
                "a stack address fits a count and a tag");
  static_assert(rt::alloc::heapAddressBits <= lengthBits && stackAddressBits <= lengthBits,
                "an array's length leaves the top bits free");

public:
  bool empty() const { return top == nullptr; }

  void push(idris_rt_header *cell) {
    auto next = reinterpret_cast<uintptr_t>(top);
    auto high = static_cast<uint32_t>(next >> addressLowBits);
    cell->count = static_cast<uint32_t>(next);
    if (uint64_t *length = steppedLength(cell))
      *length |= uint64_t{high} << lengthBits;
    else
      cell->info = (cell->info & ~tagField) | high;
    top = cell;
  }

  idris_rt_header *pop() {
    idris_rt_header *cell = top;
    uint64_t high = cell->info & tagField;
    if (uint64_t *length = steppedLength(cell)) {
      high = *length >> lengthBits;
      *length &= lengthField;
    }
    uintptr_t next = uintptr_t{cell->count} | static_cast<uintptr_t>(high) << addressLowBits;
    top = reinterpret_cast<idris_rt_header *>(next);
    return cell;
  }

private:
  idris_rt_header *top = nullptr;
};

// A cell's object slots: right after the header, one word each, in a thunk
// as in a box. Strings and bignums have none.
void **slotsOf(idris_rt_header *cell) {
  return static_cast<void **>(static_cast<void *>(cell + 1));
}

void releaseSlots(void **slots, uint32_t objs, Dying &dying) {
  for (uint32_t i = 0; i < objs; ++i)
    if (idris_rt_header *dead = rt::rc::lastReference(slots[i]))
      dying.push(dead);
}

// Releases what a cell owns besides its memory: its object slots, which an
// array has per element. A bignum's digits are in its cell.
void releaseOwned(idris_rt_header *cell, Dying &dying) {
  uint32_t objs = idris_rt_info_objs(cell->info);
  if (idris_rt_info_kind(cell->info) != IDRIS_RT_KIND_ARRAY) {
    releaseSlots(slotsOf(cell), objs, dying);
    return;
  }
  if (objs == 0)
    return;
  auto *array = reinterpret_cast<idris_rt_array *>(cell);
  char *element = reinterpret_cast<char *>(array + 1);
  size_t stride = idris_rt_info_tag(cell->info);
  for (uint64_t i = 0; i < array->length; ++i, element += stride)
    releaseSlots(static_cast<void **>(static_cast<void *>(element)), objs, dying);
}

// A dead cell's memory is freed, but a stack cell's belongs to its frame:
// there the count becomes 0, so the dead cell is inert.
void freeDead(idris_rt_header *cell) {
  if (rt::rc::isStack(cell->info))
    cell->count = 0;
  else
    rt::alloc::freeCell(cell);
}

void releaseAll(Dying &dying) {
  while (!dying.empty()) {
    idris_rt_header *cell = dying.pop();
    releaseOwned(cell, dying);
    freeDead(cell);
  }
}

} // namespace

namespace rt::rc {

// Out of line, so that the inlined decrement stays a test and a store.
[[gnu::noinline]] void release(idris_rt_header *cell) {
  Dying dying;
  dying.push(cell);
  releaseAll(dying);
}

// What a persistent cell holds, released without freeing the cell: its
// memory is the program's, and its header stays.
void releaseHeld(idris_rt_header *cell) {
  Dying dying;
  releaseOwned(cell, dying);
  releaseAll(dying);
}

} // namespace rt::rc
