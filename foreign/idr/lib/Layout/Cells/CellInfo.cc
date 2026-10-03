// The info word of a cell's header.
module;
#include "idris_rt.h"

module idr.layout;

import idr.mlir;

using namespace mlir;

namespace idr::layout {

CellInfo::CellInfo(uint32_t word) noexcept : bits(word) {}

std::expected<CellInfo, std::string> CellInfo::box(uint64_t tag, uint64_t objs) noexcept {
  if (tag >= IDRIS_RT_TAG_LIMIT)
    return std::unexpected(("its tag is " + Twine(tag) + ", and a cell's tag is below " +
                            Twine(IDRIS_RT_TAG_LIMIT))
                               .str());
  if (objs >= IDRIS_RT_OBJS_LIMIT)
    return std::unexpected(("it holds " + Twine(objs) +
                            " counted references (strings, boxed values, closures, "
                            "Integers, Nats), and a cell holds at most " +
                            Twine(IDRIS_RT_OBJS_LIMIT - 1))
                               .str());
  return CellInfo(idris_rt_info(static_cast<uint32_t>(tag), static_cast<uint32_t>(objs),
                                IDRIS_RT_KIND_BOX));
}

std::expected<CellInfo, std::string> CellInfo::closure(uint64_t objs) noexcept {
  if (objs >= IDRIS_RT_OBJS_LIMIT)
    return std::unexpected(("its captures hold " + Twine(objs) +
                            " counted references, and a cell holds at most " +
                            Twine(IDRIS_RT_OBJS_LIMIT - 1))
                               .str());
  return CellInfo(idris_rt_info(0, static_cast<uint32_t>(objs), IDRIS_RT_KIND_CLOSURE));
}

std::expected<CellInfo, std::string> CellInfo::array(uint64_t stride, uint64_t objs) noexcept {
  if (stride >= IDRIS_RT_TAG_LIMIT)
    return std::unexpected(("an element takes " + Twine(stride) +
                            " bytes, and an array's element takes fewer than " +
                            Twine(IDRIS_RT_TAG_LIMIT))
                               .str());
  if (objs >= IDRIS_RT_OBJS_LIMIT)
    return std::unexpected(("an element holds " + Twine(objs) +
                            " counted references, and an array's element holds at most " +
                            Twine(IDRIS_RT_OBJS_LIMIT - 1))
                               .str());
  return CellInfo(idris_rt_info(static_cast<uint32_t>(stride), static_cast<uint32_t>(objs),
                                IDRIS_RT_KIND_ARRAY));
}

CellInfo CellInfo::string(bool ascii) noexcept {
  return CellInfo(idris_rt_info(ascii ? 1u : 0u, 0, IDRIS_RT_KIND_STRING));
}

CellInfo CellInfo::bignum() noexcept { return CellInfo(idris_rt_info(0, 0, IDRIS_RT_KIND_BIGNUM)); }

uint32_t CellInfo::word() const noexcept { return bits; }

CellInfo CellInfo::onStack() const noexcept { return CellInfo(bits | IDRIS_RT_STACK_CELL); }

} // namespace idr::layout
