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

// The cells whose count reached 0 and whose references are still to be
// released: a stack threaded through the cells. A dying cell's count and
// tag are dead, 48 bits, which hold the next cell's address: a heap cell's
// has no more bits than the allocator's pagemap covers (rt.alloc), and a
// stack cell's no more than the target's stacks (above). Its objs, kind and
// stack bit, which releasing it reads, stay.
class Dying {
  static_assert(rt::alloc::heapAddressBits <= 32 + 16, "a heap address fits a count and a tag");
  static_assert(stackAddressBits <= 32 + 16, "a stack address fits a count and a tag");

public:
  bool empty() const { return top == nullptr; }

  void push(idris_rt_header *cell) {
    auto next = reinterpret_cast<uintptr_t>(top);
    cell->count = static_cast<uint32_t>(next);
    cell->info = (cell->info & 0xFFFF0000u) | static_cast<uint32_t>(next >> 32);
    top = cell;
  }

  idris_rt_header *pop() {
    idris_rt_header *cell = top;
    uintptr_t next = uintptr_t{cell->count} | uintptr_t{cell->info & 0xFFFFu} << 32;
    top = reinterpret_cast<idris_rt_header *>(next);
    return cell;
  }

private:
  idris_rt_header *top = nullptr;
};

// A cell's object slots: after the header, and in a closure after its code
// pointer too. Strings and bignums have none.
void **slotsOf(idris_rt_header *cell) {
  size_t offset = idris_rt_info_kind(cell->info) == IDRIS_RT_KIND_CLOSURE ? 16 : 8;
  return static_cast<void **>(static_cast<void *>(reinterpret_cast<char *>(cell) + offset));
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

} // namespace rt::rc
