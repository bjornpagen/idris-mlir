// idr.layout:cells: a cell, as the runtime reads it: its header's info
// word, the slots of its components, the elements of an array, and the
// mark of a cell that lives in a stack frame.
module;
// The runtime's C ABI: its limits and its header are macros and C.
#include "idris_rt.h"

export module idr.layout:cells;

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
  // A closure's code pointer says what it is, so its tag is 0.
  static std::expected<CellInfo, std::string> closure(uint64_t objs) noexcept;
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
  uint32_t bits;
};

// The tag of a box, the low bits of its info word (idris_rt_info_tag).
constexpr uint32_t tagMask = IDRIS_RT_TAG_LIMIT - 1;

// One component of a value stored in a heap cell or static data.
struct Slot {
  mlir::Type type;
  unsigned offset;
};

// A box or a closure: a cell is the header (idris_rt_header: the count,
// then the info word, IDRIS_RT_WORD_BYTES together), then its components.
// The counted components come first, one pointer-sized word each, as the
// runtime's object slots: right after the header in a box, after the code
// pointer in a closure. The others follow, each at the size and alignment
// the target's data layout gives its type. A cell starts and ends on a
// word boundary.
struct Cell {
  // For each field (of a constructor) or capture (of a closure, the code
  // pointer first), the slots of its components.
  llvm::SmallVector<llvm::SmallVector<Slot>> fields;
  unsigned size = IDRIS_RT_WORD_BYTES;
  // The number of object slots.
  unsigned objs = 0;
  // Every component, (field, component) in address order.
  llvm::SmallVector<std::pair<unsigned, unsigned>> order;
  // The header's info word, which counts the object slots.
  CellInfo info;
};

// An element of an array (idris_rt_array): its components in their slots,
// at offsets from the element's start, laid out as a cell's fields are
// (object slots first); the element's size, which is the array's stride;
// and the info word of the array's cell.
struct Element {
  llvm::SmallVector<Slot> slots;
  unsigned stride;
  CellInfo info;
};

// The unit attribute of an idr.con whose cell idr-stack puts in its
// function's frame, and idr-lower builds there: counted as any cell, but
// never freed and never exclusive (IDRIS_RT_STACK_CELL).
inline constexpr llvm::StringLiteral stackMark = "idr.stack";

} // namespace idr::layout
