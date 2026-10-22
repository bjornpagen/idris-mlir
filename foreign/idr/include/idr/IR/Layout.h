// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How idr values are represented at run time, as the runtime (idris_rt.h)
// reads them: the components of every value type, each with the kind of
// word it is; the cells of the data types held in a cell, the slots of
// those held in place and the elements of arrays, decided once per module
// for its target (Layouts). Whether a data type is held in place or in a
// cell is its own fact, computed when the type is made (its layout, the
// class rule of lib/IR/Layout/Classes.cpp); what is here is the bytes. Every
// value has a layout: a cell whose header cannot count its object slots
// counts them in a word after the header, a sum of more constructors than a
// header's tag holds keeps its constructor's group in an object slot of
// every cell, and an element an array's header cannot describe is held in a
// cell of its own. No count refuses a program.

#ifndef IDR_IR_LAYOUT_H
#define IDR_IR_LAYOUT_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/DenseMap.h"
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

// The tag of a cell within its group, the low bits of its info word
// (idris_rt_info_tag); the group is the rest of the tag.
inline constexpr uint32_t tagMask = IDRIS_RT_TAG_LIMIT - 1;

// The info word of a cell's header, which the runtime reads to free the cell
// (idris_rt_info: the tag, the number of object slots, the kind). A CellInfo
// is made only from fields that fit, so no field of a word overflows into
// the next: a constructor's tag is taken within its group, a count the field
// cannot hold is marked as counted after the header, and an array's element
// that does not fit is held in a cell before its word is made.
class CellInfo {
public:
  // A constructor's cell, the header holding its tag within its group.
  // `objs` is the number of object slots the header counts, or nothing
  // when the word after the header counts them.
  static CellInfo constructor(Tag tag, std::optional<unsigned> objs) noexcept;
  // A memo cell in the state of the constructor `tag`: laid out and freed
  // as a constructor's cell, and of its own kind, which says that a force
  // may write it.
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

private:
  explicit CellInfo(uint32_t word) noexcept;
  static CellInfo withKind(Tag tag, std::optional<unsigned> objs, uint32_t kind) noexcept;
  uint32_t bits;
};

// The kind of word a component is, which decides how a count is kept of it
// and so which runtime entry increments and decrements it: no count; a
// pointer to a cell, never null; a pointer that may be null (a slot of a
// value in place that another constructor leaves empty, a reuse token); a
// big's word, a small integer or a cell's address; a slot that may be any
// of these. A lattice: Cell below MaybeCell and Big, their join Any.
enum class Word : uint8_t { Uncounted, Cell, MaybeCell, Big, Any };

// The least kind both `a` and `b` stand in.
constexpr Word join(Word a, Word b) {
  if (a == b || b == Word::Uncounted)
    return a;
  if (a == Word::Uncounted)
    return b;
  if ((a == Word::Cell && b == Word::MaybeCell) || (a == Word::MaybeCell && b == Word::Cell))
    return Word::MaybeCell;
  return Word::Any;
}

// One runtime component of a value, and the kind of word it is: the type
// and the kind are one fact, so no reader pairs two lists by position.
struct Component {
  mlir::Type type;
  Word word;

  bool counted() const { return word != Word::Uncounted; }
};

// A component placed in a cell or an element, at its offset from the start.
struct Slot : Component {
  unsigned offset;
};

// A word after the header that a cell holds of itself, by value: the count
// of its object slots where the header cannot count them, and its
// constructor's group in a sum of more constructors than a header's tag
// holds. The header itself is no OwnWord: its count is 1 on the heap and 0
// in static data, and its info word is the cell's own, so each writer gives
// the header as its parameter.
struct OwnWord {
  mlir::Type type;
  unsigned offset;
  int64_t value;
};

// A constructor's cell, or a memo cell in one of its states: the header
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
  // The words after the header the cell holds of itself, in address order.
  llvm::SmallVector<OwnWord> words;
};

// The cells of a data type whose layout is a cell, each constructor's at its
// allocation size: a memo sum's every state at its largest state's, since a
// memo cell is allocated in one state and written into another.
struct CellLayout {
  // For a sum of more constructors than a header's tag holds, the offset of
  // the group word, one offset in every cell of the sum, so a match reads
  // it before it knows the constructor.
  std::optional<unsigned> group;
  // By tag.
  llvm::SmallVector<Cell> cells;

  const Cell &cell(Tag tag) const { return cells[static_cast<uint32_t>(tag)]; }
};

// An element of an array (idris_rt_array): its components in their slots,
// at offsets from the element's start, laid out as a cell's fields are
// (object slots first); the element's size, which is the array's stride;
// and the info word of the array's cell. An element whose size or object
// slots the array's header cannot describe is held in a cell of its own,
// one counted pointer in the array.
struct Element {
  llvm::SmallVector<Slot> slots;
  unsigned stride;
  CellInfo info;
  std::optional<Cell> boxed;
};

// A data type held in place, spread over its words: the tag, where two
// constructors or more are possible, then the slots of the possible
// constructors' fields. A slot one constructor leaves empty is null there,
// so a slot that holds a cell's pointer for some constructors and nothing
// for others may be null, and the references of a value in place are
// exactly its counted words.
struct SumLayout {
  std::optional<mlir::IntegerType> tag;
  llvm::SmallVector<Component> words;
  // For each declared constructor, by tag: for each field, the words of its
  // components, as indices into `words`; none for a constructor the
  // indices exclude.
  llvm::SmallVector<llvm::SmallVector<llvm::SmallVector<unsigned>>> fields;

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
// type says, decided once from the type.
struct DescriptorFields {
  DescriptorField offset;
  llvm::SmallVector<DescriptorField> sizes;
  std::optional<llvm::SmallVector<DescriptorField>> strides;

  unsigned carried() const;
  static DescriptorFields of(mlir::ShapedType type);
};

// How many runtime components a value of `type` takes: a data type's, as its
// layout says (none for a value in place no constructor of which holds
// any); an array's cell and the fields of its descriptor its type does not
// fix; one for every other value.
uint32_t componentCount(mlir::Type type);

// Whether everything a value of `type` reaches is bounded by its type: a
// data type's answer, computed when it was made; any other value bounds it
// exactly where it holds no reference, since a string, a big, an array and
// a closure not yet defunctionalized each reach cells sized at run time.
Reach reachOf(mlir::Type type);

// What two parts reach together: bounded only where both are.
constexpr Reach join(Reach a, Reach b) { return a == Reach::Unbounded ? a : b; }

// idr's comparison of two values held as words, as a signed comparison of
// the words: a big's small words and the runtime's three-way result both
// order that way.
mlir::arith::CmpIPredicate signedPredicate(CmpPredicate predicate);

} // namespace idr::layout

namespace idr {

// The layouts of the values of a module, placed as its target lays them
// out: what idr-lower builds values in, and what counting sizes cells by.
// Every data type a value of the module holds, and every one their fields
// hold, has its slots or its cells computed by the constructor, and nothing
// changes after it, so passes running in parallel read it without a lock.
// What is counted is the same on every target; what a component takes in
// bytes is the target's.
class Layouts {
public:
  // The layouts of `root`, a module or a program, for the target its data
  // layout describes, whose pointers are the runtime's words, as the
  // program's verifier holds.
  explicit Layouts(mlir::Operation *root);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<Layouts>();
  }

  // The runtime components of a value type.
  llvm::SmallVector<layout::Component> components(mlir::Type type) const;
  // The slots of `type`, a data type held in place.
  const layout::SumLayout &sum(DataType type) const;
  // The cells of `type`, a data type held in a cell.
  const layout::CellLayout &cells(DataType type) const;
  // The bytes a component of type `component` takes, as the target lays it
  // out.
  unsigned sizeOf(mlir::Type component) const;
  // The element layout of an array of `element`.
  layout::Element element(mlir::Type element) const;

private:
  unsigned alignmentOf(mlir::Type component) const;
  void record(mlir::Type component);
  // The cell of a constructor of `fieldTypes`, object slots first.
  layout::Cell cellOf(llvm::ArrayRef<llvm::SmallVector<layout::Component>> fields, Tag tag,
                      bool grouped, MemberKind kind) const;
  // The components of each field of constructor `tag` of `type`, at its
  // application where its indices determine its binders, at an unknown
  // index otherwise.
  llvm::SmallVector<llvm::SmallVector<layout::Component>> fieldsOf(DataType type, Tag tag) const;
  layout::SumLayout sumOf(DataType type) const;
  layout::CellLayout cellsOf(DataType type) const;

  mlir::Operation *root;
  llvm::DenseMap<DataType, std::unique_ptr<layout::SumLayout>> sums;
  llvm::DenseMap<DataType, layout::CellLayout> cellLayouts;
  llvm::DenseMap<mlir::Type, std::pair<unsigned, unsigned>> measures;
};

} // namespace idr

#endif // IDR_IR_LAYOUT_H
