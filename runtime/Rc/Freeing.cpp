// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Releasing a dead cell's references and freeing it, through the dying
// list.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Platform/Address.h"
#include "Rc/Rc.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace {

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
// pagemap covers (rt::alloc), and a stack cell's no more than the target's
// user address space (rt::platform).
class Dying {
  static_assert(rt::alloc::heapAddressBits <= addressLowBits + addressHighBits,
                "a heap address fits a count and a tag");
  static_assert(rt::platform::userAddressBits <= addressLowBits + addressHighBits,
                "a stack address fits a count and a tag");
  static_assert(rt::alloc::heapAddressBits <= lengthBits &&
                    rt::platform::userAddressBits <= lengthBits,
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

// Each object slot of `cell`, which an array has per element. A box's or a
// thunk's are right after the header, one word each, or, when the header's
// objs is IDRIS_RT_OBJS_WIDE, after the word that counts them: this is the
// one place the runtime reads a cell's slots, for a death and for a static
// memo cell's persistence alike. Strings and bignums have none (objs 0), and
// a bignum's digits are in its cell. An array's objs is always the count,
// never the mark: an element with that many slots is held boxed. Dying
// keeps objs and the count word, so a dying cell is read alike.
template <typename Each>
void eachSlot(idris_rt_header *cell, Each each) {
  uint32_t objs = idris_rt_info_objs(cell->info);
  auto slots = [&](void **at, uint64_t n) {
    for (uint64_t i = 0; i < n; ++i)
      each(at[i]);
  };
  if (idris_rt_info_kind(cell->info) != IDRIS_RT_KIND_ARRAY) {
    auto *after = static_cast<uint64_t *>(static_cast<void *>(cell + 1));
    if (objs == IDRIS_RT_OBJS_WIDE) [[unlikely]]
      slots(static_cast<void **>(static_cast<void *>(after + 1)), *after);
    else
      slots(static_cast<void **>(static_cast<void *>(after)), objs);
    return;
  }
  if (objs == 0)
    return;
  auto *array = reinterpret_cast<idris_rt_array *>(cell);
  char *element = reinterpret_cast<char *>(array + 1);
  size_t stride = idris_rt_info_tag(cell->info);
  for (uint64_t i = 0; i < array->length; ++i, element += stride)
    slots(static_cast<void **>(static_cast<void *>(element)), objs);
}

// Releases what a cell owns besides its memory: its object slots.
void releaseOwned(idris_rt_header *cell, Dying &dying) {
  eachSlot(cell, [&](void *slot) {
    if (idris_rt_header *dead = rt::rc::lastReference(slot))
      dying.push(dead);
  });
}

// A dead cell's memory is freed, but a stack cell's belongs to its frame:
// there the count becomes 0, so the dead cell is inert, and in the checked
// runtime it is marked as a heap cell that died is, until its op runs again
// and writes its header anew.
void freeDead(idris_rt_header *cell) {
  if (!rt::rc::isStack(cell->info)) {
    rt::alloc::freeCell(cell);
    return;
  }
  cell->count = 0;
  if constexpr (rt::alloc::checked)
    cell->info = rt::alloc::freedInfo;
}

// The cells that died while others were released, each released and freed
// in turn. Each enters once, when its count reaches 0, so the list ends.
void releaseDying(Dying &dying) {
  while (!dying.empty()) {
    idris_rt_header *cell = dying.pop();
    releaseOwned(cell, dying);
    freeDead(cell);
  }
}

} // namespace

namespace rt::rc {

// Out of line, so that the inlined decrement stays a test and a store. The
// cell that died first is released directly, not pushed and popped: most
// deaths free one cell, and that cell's header is then written once less.
[[gnu::noinline]] void release(idris_rt_header *cell) {
  Dying dying;
  releaseOwned(cell, dying);
  freeDead(cell);
  releaseDying(dying);
}

// The cells still to be walked are kept in a block of the runtime's memory
// that grows as the walk needs, freed when it ends: a persisted cell's
// header must keep its tag, so the walk cannot thread through it as dying
// cells do. Each cell enters once, when its count becomes 0, so the walk
// ends.
void persistHeld(idris_rt_header *cell) {
  size_t size = 16, top = 0;
  auto **stack = static_cast<idris_rt_header **>(rt::alloc::allocate(size * sizeof(void *)));
  auto persist = [&](void *slot) {
    if (!isObject(slot))
      return;
    idris_rt_header *held = headerOf(slot);
    touch(held);
    if (held->count == 0 || isStack(held->info))
      return;
    held->count = 0;
    rt::alloc::forgetCell();
    if (top == size) {
      size *= 2;
      stack = static_cast<idris_rt_header **>(
          rt::alloc::reallocate(stack, size * sizeof(void *)));
    }
    stack[top++] = held;
  };
  eachSlot(cell, persist);
  while (top != 0)
    eachSlot(stack[--top], persist);
  rt::alloc::release(stack);
}

} // namespace rt::rc
