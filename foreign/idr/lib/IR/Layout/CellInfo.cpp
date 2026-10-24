// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The info word of a cell's header, as the runtime's idris_rt_info packs it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"

#include "idris_rt.h"

using namespace mlir;

namespace idr::layout {

CellInfo::CellInfo(uint32_t word) noexcept : bits(word) {}

// The header holds the tag within its group, the cell's group word the
// rest; and the count of object slots, or the mark that the word after the
// header holds it. A count is given only where the header's field holds it
// (Layouts::cellOf).
CellInfo CellInfo::fields(Tag tag, std::optional<unsigned> objs) noexcept {
  uint32_t field = objs ? *objs : IDRIS_RT_OBJS_WIDE;
  return CellInfo(idris_rt_info(static_cast<uint32_t>(tag) & tagMask, field, IDRIS_RT_KIND_FIELDS));
}

// Layouts::element makes one only of an element the header describes.
CellInfo CellInfo::array(unsigned stride, unsigned objs) noexcept {
  return CellInfo(idris_rt_info(stride, objs, IDRIS_RT_KIND_ARRAY));
}

uint32_t CellInfo::word() const noexcept { return bits; }

} // namespace idr::layout
