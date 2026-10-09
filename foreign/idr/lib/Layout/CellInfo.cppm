// idr.layout:cellinfo: the info word of a cell's header.
module;
// The runtime's C ABI: its limits and its header are macros and C.
#include "idris_rt.h"

export module idr.layout:cellinfo;

import idr.mlir;

export namespace idr::layout {

// The info word of a cell's header, which the runtime reads to free the cell
// (idris_rt_info: the tag, the number of object slots, the kind). A CellInfo
// exists only for a tag and an object count that fit their fields, so a word
// whose fields overflow into each other cannot be written; the factories say
// why when they do not fit.
class CellInfo {
public:
  static std::expected<CellInfo, std::string> box(uint64_t tag, uint64_t objs) noexcept;
  // A memo cell in the state of the constructor `tag`: laid out and freed
  // as a box, and of its own kind, which says that a force may write it.
  static std::expected<CellInfo, std::string> thunk(uint64_t tag, uint64_t objs) noexcept;
  // An array's: the tag is the element's size in bytes, its objs the object
  // slots each element starts with.
  static std::expected<CellInfo, std::string> array(uint64_t stride, uint64_t objs) noexcept;
  static CellInfo string(bool ascii) noexcept;
  static CellInfo bignum() noexcept;

  uint32_t word() const noexcept;
  // The same cell in a stack frame.
  CellInfo onStack() const noexcept;

private:
  explicit CellInfo(uint32_t word) noexcept;
  // A box's word or a memo cell's, which differ only in the kind.
  static std::expected<CellInfo, std::string> constructor(uint64_t tag, uint64_t objs,
                                                          uint32_t kind) noexcept;
  uint32_t bits;
};

// The tag of a box, the low bits of its info word (idris_rt_info_tag).
constexpr uint32_t tagMask = IDRIS_RT_TAG_LIMIT - 1;

} // namespace idr::layout

using namespace mlir;

namespace idr::layout {

CellInfo::CellInfo(uint32_t word) noexcept : bits(word) {}

std::expected<CellInfo, std::string> CellInfo::constructor(uint64_t tag, uint64_t objs,
                                                           uint32_t kind) noexcept {
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
  return CellInfo(idris_rt_info(static_cast<uint32_t>(tag), static_cast<uint32_t>(objs), kind));
}

std::expected<CellInfo, std::string> CellInfo::box(uint64_t tag, uint64_t objs) noexcept {
  return constructor(tag, objs, IDRIS_RT_KIND_BOX);
}

std::expected<CellInfo, std::string> CellInfo::thunk(uint64_t tag, uint64_t objs) noexcept {
  return constructor(tag, objs, IDRIS_RT_KIND_THUNK);
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
