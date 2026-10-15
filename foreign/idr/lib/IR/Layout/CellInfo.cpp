// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The info word of a cell's header, as the runtime's idris_rt_info packs it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"

#include "idris_rt.h"

#include <cassert>

using namespace mlir;

namespace idr::layout {

CellInfo::CellInfo(uint32_t word) noexcept : bits(word) {}

// The header holds the tag within its group, the cell's group word the
// rest; and the count of object slots, or the mark that the word after the
// header holds it.
CellInfo CellInfo::constructor(uint64_t tag, std::optional<unsigned> objs,
                               uint32_t kind) noexcept {
  assert((!objs || *objs <= mostObjects) && "a count the header's field holds");
  uint32_t field = objs ? *objs : IDRIS_RT_OBJS_WIDE;
  return CellInfo(idris_rt_info(static_cast<uint32_t>(tag & tagMask), field, kind));
}

CellInfo CellInfo::box(uint64_t tag, std::optional<unsigned> objs) noexcept {
  return constructor(tag, objs, IDRIS_RT_KIND_BOX);
}

CellInfo CellInfo::thunk(uint64_t tag, std::optional<unsigned> objs) noexcept {
  return constructor(tag, objs, IDRIS_RT_KIND_THUNK);
}

CellInfo CellInfo::array(unsigned stride, unsigned objs) noexcept {
  assert(stride < IDRIS_RT_TAG_LIMIT && objs <= mostObjects &&
         "an element the array's header describes, as Layouts::element lays one out");
  return CellInfo(idris_rt_info(stride, objs, IDRIS_RT_KIND_ARRAY));
}

CellInfo CellInfo::string(bool ascii) noexcept {
  return CellInfo(idris_rt_info(ascii ? 1u : 0u, 0, IDRIS_RT_KIND_STRING));
}

CellInfo CellInfo::bignum() noexcept { return CellInfo(idris_rt_info(0, 0, IDRIS_RT_KIND_BIGNUM)); }

uint32_t CellInfo::word() const noexcept { return bits; }

CellInfo CellInfo::onStack() const noexcept { return CellInfo(bits | IDRIS_RT_STACK_CELL); }

} // namespace idr::layout
