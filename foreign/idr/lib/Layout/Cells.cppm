// idr.layout:cells: a cell, as the runtime reads it: its header's info
// word, the slots of its components, the elements of an array, and the
// mark of a cell that lives in a stack frame.
module;
// The runtime's C ABI: its limits and its header are macros and C.
#include "idris_rt.h"

export module idr.layout:cells;

import idr.mlir;

import :cellinfo;

export namespace idr::layout {

// One component of a value stored in a heap cell or static data.
struct Slot {
  mlir::Type type;
  unsigned offset;
};

// A box, or a memo cell in one of its states: a cell is the header
// (idris_rt_header: the count, then the info word, IDRIS_RT_WORD_BYTES
// together), then its components. The counted components come first, one
// pointer-sized word each, right after the header, as the runtime's object
// slots. The others follow, each at the size and alignment the target's
// data layout gives its type. A cell starts and ends on a word boundary,
// and holds no code address.
struct Cell {
  // For each field of the constructor, the slots of its components.
  llvm::SmallVector<llvm::SmallVector<Slot>> fields;
  // The bytes allocated for the cell: a memo cell's are its largest
  // state's, whichever state it is built in.
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
