// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How idr values are represented at runtime, as the runtime (idris_rt.h)
// reads them: the components of every value type, each with whether it is
// counted; the cells of boxes, memo sums and arrays and the slots of sums
// held in place, decided once per module for its target (Layouts); and the
// boxes that make every type that contains itself finite (fit), decided
// from the module's types. Every value has a layout: a cell whose header
// cannot count its object slots counts them in a word after the header, a
// sum of more constructors than a header's tag holds keeps its constructor's
// group in an object slot of every cell, and an element an array's header
// cannot describe is held in a cell of its own. No count refuses a program.

#ifndef IDR_IR_LAYOUT_H
#define IDR_IR_LAYOUT_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include "idris_rt.h"

#include <memory>
#include <optional>
#include <utility>
#include <variant>

namespace idr::layout {

// The most object slots a header's objs field counts. A cell of more holds
// their number in the word right after its header, and its objs field is
// IDRIS_RT_OBJS_WIDE, which says so to the runtime; an array's element of
// more is held in a cell of its own.
inline constexpr unsigned mostObjects = IDRIS_RT_OBJS_WIDE - 1;

// The tag of a box within its group, the low bits of its info word
// (idris_rt_info_tag); the group is the rest of the tag.
inline constexpr uint32_t tagMask = IDRIS_RT_TAG_LIMIT - 1;

// The info word of a cell's header, which the runtime reads to free the cell
// (idris_rt_info: the tag, the number of object slots, the kind). A CellInfo
// is made only from fields that fit, so no field of a word overflows into
// the next: a constructor's tag is taken within its group, a count the field
// cannot hold is marked as counted after the header, and an array's element
// that does not fit is boxed before its word is made.
class CellInfo {
public:
  // A box in the constructor `tag`, the header holding its tag within its
  // group. `objs` is the number of object slots the header counts, or
  // nothing when the word after the header counts them.
  static CellInfo box(Tag tag, std::optional<unsigned> objs) noexcept;
  // A memo cell in the state of the constructor `tag`: laid out and freed
  // as a box, and of its own kind, which says that a force may write it.
  static CellInfo thunk(Tag tag, std::optional<unsigned> objs) noexcept;
  // An array's: the tag is the element's size in bytes, below
  // IDRIS_RT_TAG_LIMIT, its objs the object slots each element starts
  // with, at most mostObjects.
  static CellInfo array(unsigned stride, unsigned objs) noexcept;
  // A string's: whether it is ASCII is its scalar count against its byte
  // count, which the cell holds, so the header says nothing of it.
  static CellInfo string() noexcept;
  static CellInfo bignum() noexcept;

  uint32_t word() const noexcept;
  // The same cell in a stack frame.
  CellInfo onStack() const noexcept;

private:
  explicit CellInfo(uint32_t word) noexcept;
  // A box's word or a memo cell's, which differ only in the kind.
  static CellInfo constructor(Tag tag, std::optional<unsigned> objs, uint32_t kind) noexcept;
  uint32_t bits;
};

// One runtime component of a value, and whether it is counted: a value that
// holds a reference itself (a cell's address, a big's word, an array's
// cell), or a counted slot of a sum. The type and the bit are one fact, so
// no reader pairs two lists by position.
struct Component {
  mlir::Type type;
  bool counted;
};

// A component placed in a cell or an element, at its offset from the start.
struct Slot : Component {
  unsigned offset;
};

// A word after the header that a cell holds of itself, by value: the count
// of its object slots where the header cannot count them, and its
// constructor's group in a sum of more constructors than a header's tag
// holds. The header itself is no OwnWord: its count is 1 on the heap and in
// a frame and 0 in static data, and its info word is the cell's own, the
// same marked as a stack cell's, or a memo state's or'ed with the stack mark
// the cell has, so each writer gives the header as its parameter.
struct OwnWord {
  mlir::Type type;
  unsigned offset;
  int64_t value;
};

// A box, or a memo cell in one of its states: a cell is the header
// (idris_rt_header: the count, then the info word, IDRIS_RT_WORD_BYTES
// together), then its own words, then its object slots, one pointer-sized
// word each, then its other components, each at the size and alignment the
// target's data layout gives its type. The object slots are the group of a
// sum of more constructors than a header's tag holds, then the counted
// components. A cell starts and ends on a word boundary, and holds no code
// address.
struct Cell {
  // For each field of the constructor, the slots of its components.
  llvm::SmallVector<llvm::SmallVector<Slot>> fields;
  // The bytes allocated for the cell: a memo cell's are its largest
  // state's, whichever state it is built in.
  unsigned size = IDRIS_RT_WORD_BYTES;
  // The number of object slots, the group's among them.
  unsigned objs = 0;
  // Every component, (field, component), in address order.
  llvm::SmallVector<std::pair<unsigned, unsigned>> order;
  // The header's info word.
  CellInfo info;
  // The words after the header the cell holds of itself, in address order:
  // the count of its object slots (an i64, `objs`) where the header cannot
  // count them, then, for a sum of more constructors than a header's tag
  // holds, the constructor's group (an i64), held as a small Integer holds
  // its value, so the runtime releases it as it releases any small Integer:
  // not at all.
  llvm::SmallVector<OwnWord> words;
};

// The cells of a data type some value holds in a box, each constructor's at
// its allocation size: a memo sum's every state at its largest state's,
// since a memo cell is allocated in one state and written into another.
struct BoxLayout {
  // For a sum of more constructors than a header's tag holds, the offset of
  // the group word, one offset in every cell of the sum, so a match reads
  // it before it knows the constructor: the tag is the group times
  // IDRIS_RT_TAG_LIMIT plus the header's tag.
  std::optional<unsigned> group;
  // By tag.
  llvm::SmallVector<Cell> cells;

  const Cell &cell(Tag tag) const { return cells[static_cast<uint32_t>(tag)]; }
};

// An element of an array (idris_rt_array): its components in their slots,
// at offsets from the element's start, laid out as a cell's fields are
// (object slots first); the element's size, which is the array's stride;
// and the info word of the array's cell. An element whose size or object
// slots the array's header cannot describe is held boxed: the element is
// one counted pointer to a cell of its own, `boxed`, which holds the value
// as a box of one field holds it.
struct Element {
  llvm::SmallVector<Slot> slots;
  unsigned stride;
  CellInfo info;
  std::optional<Cell> boxed;
};

// A sum held in place, spread over its words: the tag, when the sum has
// one, then the slots of its constructors' fields. A slot that holds a
// counted component in one constructor (a pointer to a cell, or a big)
// holds one in every constructor that uses it, and null in those that do
// not, so that the references of a sum are exactly its counted words.
struct SumLayout {
  // The integer the constructor's tag is held in, words[0], for a sum of
  // two constructors or more; a sum of fewer has no tag to hold.
  std::optional<mlir::IntegerType> tag;
  llvm::SmallVector<Component> words;
  // For each constructor, by tag: for each field, the words of its
  // components, as indices into `words`.
  llvm::SmallVector<llvm::SmallVector<llvm::SmallVector<unsigned>>> fields;

  // The words of the components of field `field` of the constructor `ctor`.
  llvm::ArrayRef<unsigned> slotsOf(Tag ctor, unsigned field) const {
    return fields[static_cast<uint32_t>(ctor)][field];
  }
};

// A field of a memref's descriptor (offset, size or stride): a number its
// type fixes, or carried by the value as a component of its own.
struct Fixed {
  int64_t value;
};
struct Carried {};
using DescriptorField = std::variant<Fixed, Carried>;

// What a memref's (or a tensor's) descriptor holds besides its cell, as its
// type says, decided once from the type: every walk over the descriptor
// (taking components apart, packing them, Layouts::components) iterates
// this plan, so they cannot disagree on which fields a value carries.
// `strides` is none for an identity layout and a tensor, whose strides are
// the row-major products of the sizes, computed where they are needed:
// carrying them would take registers for what the sizes say.
struct DescriptorFields {
  DescriptorField offset;
  llvm::SmallVector<DescriptorField> sizes;
  std::optional<llvm::SmallVector<DescriptorField>> strides;

  // How many fields the value carries: its components after the cell.
  unsigned carried() const;

  // The plan of `type`. A layout other than the identity is read through
  // getStridesAndOffset, a strided layout and an affine map alike; one it
  // cannot read is an internal error, since the program's verifier refuses
  // a memref value whose layout is not strided.
  static DescriptorFields of(mlir::ShapedType type);
};

// Whether a value of `type` has no runtime component at all: the world, and
// a data type held in place of at most one constructor whose every field
// holds none (a unit, a pair of the world and a unit). A data type met again
// on the way holds one: a containment cycle, which fit boxes. The one
// decision of "no runtime form": components gives none by it, and nothing
// else does.
bool holdsNoComponent(mlir::Type type);

// Makes finite every data type that contains itself: each data type on a
// cycle of containment in place (TypeGraph::containsItself) becomes a box
// wherever it is held in place, with one DataRemap of kind `box`, which
// retypes `root`. A cycle passes through a box once every type on it is
// boxed, so the boxes are decided from the type graph at once. The
// frontend emits every data type in place, so this runs before anything
// reads how a value is held; after it the in-place containment is acyclic.
// Returns how many types became boxes, or fails when a body could not be
// made, which DataRemap has reported.
mlir::FailureOr<unsigned> fit(mlir::Operation *root);

// idr's comparison of two values held as words, as a signed comparison of
// the words: a big's small words and the runtime's three-way result both
// order that way.
mlir::arith::CmpIPredicate signedPredicate(CmpPredicate predicate);

} // namespace idr::layout

namespace idr {

// The layouts of the values of a module, on the components of its value
// types, placed as its target lays them out: what idr-lower builds values
// in, and what the owned stage and idr-rc size cells by. Every sum and
// every boxed data type's cells are computed by the constructor, and
// nothing changes after it, so passes running in parallel read it without
// a lock. A data type's body never changes, so it holds while the module's
// values keep their types. The components of a value type are the same on
// every target: what a component takes in bytes is the target's, and what
// is counted is not a matter of bytes.
class Layouts {
public:
  // The layouts of `root`, a module or a program, for the target its data
  // layout describes (the closest dlti.dl_spec; MLIR's defaults without
  // one), whose pointers are the runtime's words, as the program's verifier
  // holds. Every cell's header is decided here, once, and every cell can be
  // built.
  explicit Layouts(mlir::Operation *root);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<Layouts>();
  }

  // The runtime components of a value type, each with whether it is
  // counted: none for a type that holds none (holdsNoComponent), the words
  // of a sum held in place, one i64 for bigs, one pointer for every other
  // value that holds a reference (strings, boxes, memo cells included,
  // closures, suspensions, tokens) and for a destination and a cell,
  // the type itself for scalars; for an array, its cell, then the fields of
  // its descriptor its type does not fix (DescriptorFields).
  llvm::SmallVector<layout::Component> components(mlir::Type type) const;
  // The layout of the sum `type` held in place.
  const layout::SumLayout &sum(DataType type) const;

  // The bytes a component of type `component` takes in a cell, as the
  // target lays it out.
  unsigned sizeOf(mlir::Type component) const;

  // The element layout of an array of `element`: in place when the array's
  // header can describe it, else boxed.
  layout::Element element(mlir::Type element) const;

  // The cells of `type`, a data type some value holds in a box.
  const layout::BoxLayout &box(DataType type) const;

private:
  // The alignment a component of type `component` is placed at.
  unsigned alignmentOf(mlir::Type component) const;

  // A cell of `fieldTypes`, the constructor `tag`, object slots first. A
  // sum `grouped` has its group in every cell, and so a count word; any
  // other has one when its object slots outnumber what a header counts.
  layout::Cell cellOf(llvm::ArrayRef<mlir::Type> fieldTypes, Tag tag, bool grouped,
                      bool memo) const;

  mlir::Operation *root;
  // The layout of every sum a value of the module holds in place, each in
  // an allocation of its own (lib/IR/Layout/Components.cpp).
  llvm::DenseMap<DataType, std::unique_ptr<layout::SumLayout>> sums;
  // The size and alignment of every component type the data types hold,
  // measured once with the root's data layout, whose own answers are
  // remembered as they are asked and so cannot be shared between threads.
  llvm::DenseMap<mlir::Type, std::pair<unsigned, unsigned>> measures;
  llvm::DenseMap<DataType, layout::BoxLayout> boxes;
};

namespace layout {

// The layout of every sum held in place that a value of `types`, the
// module's data types, reaches through the fields of the sums it holds in
// place: each computed from the components of its fields, once.
llvm::DenseMap<DataType, std::unique_ptr<SumLayout>> sumsOf(llvm::ArrayRef<DataType> types);

// The answer of Layouts::components, each sum read from `sums`, which holds
// every sum a value of `type` holds in place.
llvm::SmallVector<Component>
components(mlir::Type type, const llvm::DenseMap<DataType, std::unique_ptr<SumLayout>> &sums);

} // namespace layout

} // namespace idr

#endif // IDR_IR_LAYOUT_H
