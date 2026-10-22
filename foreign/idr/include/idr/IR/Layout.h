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
#include "idr/Support/Footprint.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include "idris_rt.h"

#include <memory>
#include <optional>
#include <utility>
#include <variant>

// The kind of word a component is, which decides how a count is kept of it
// and so which runtime entry increments and decrements it (Word: no count; a
// pointer to a cell, never null; a pointer that may be null, a slot of a
// value in place that another constructor leaves empty or a reuse token; a
// big's word, a small integer or a cell's address; a slot that may be any
// of these), and its lattice (wordJoin), from the runtime's word kinds.
#include "idr/IR/Generated/Words.h.inc"

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

// The least kind both `a` and `b` stand in, read from the lattice the
// runtime's word kinds generate (Word, wordJoin).
constexpr Word join(Word a, Word b) {
  return wordJoin[static_cast<unsigned>(a)][static_cast<unsigned>(b)];
}

// One runtime component of a value, and the kind of word it is: the type
// and the kind are one fact, so no reader pairs two lists by position.
struct Component {
  mlir::Type type;
  Word word;

  bool counted() const { return word != Word::Uncounted; }
};

// Where a cell keeps its constructor's group: in its header's tag, which
// tells apart every constructor of a sum of at most IDRIS_RT_TAG_LIMIT, or
// in an object slot of its own, in every cell of a wider sum.
enum class GroupIn : uint8_t { HeaderTag, OwnSlot };

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

// A data type held in place, spread over its words: the tag, where it is
// laid out over two constructors or more, then the slots of those
// constructors' fields (Layouts::tagsLaidOut). A slot one constructor
// leaves empty is null there, so a slot that holds a cell's pointer for
// some constructors and nothing for others may be null, and the references
// of a value in place are exactly its counted words.
struct SumLayout {
  std::optional<mlir::IntegerType> tag;
  llvm::SmallVector<Component> words;
  // For each declared constructor, by tag: for each field, the words of its
  // components, as indices into `words`; none for a constructor it is not
  // laid out over.
  llvm::SmallVector<llvm::SmallVector<llvm::SmallVector<unsigned>>> fields;

  llvm::ArrayRef<unsigned> slotsOf(Tag ctor, unsigned field) const {
    return fields[static_cast<uint32_t>(ctor)][field];
  }
};

// How a drop of a value claimed `unique self` frees one of its fields. A
// field whose own cells the claim covers (a field of the value's own group,
// or of an in_place family) and that has cells or slots of its family is
// freed with no count read, walked as its data type, whose own fields the
// drop reads next; any other field holds data the claim says nothing of,
// dropped by its counts.
struct OwnCell {
  DataType data;
};
struct ByCount {};
using SelfDrop = std::variant<OwnCell, ByCount>;

// For each declared constructor, by tag, how a drop of a `unique self`
// value frees each of its fields.
struct OwnCells {
  llvm::SmallVector<llvm::SmallVector<SelfDrop>> fields;

  llvm::ArrayRef<SelfDrop> of(Tag ctor) const { return fields[static_cast<uint32_t>(ctor)]; }
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

// How many runtime components a value of `type` takes: a data type's, the
// count of the words it computed when it was made (none for a value in
// place no constructor of which holds any); an array's cell and the fields
// of its descriptor its type does not fix; a destination's, one per
// component of what it takes; a lifetime's, one where its kind is a value
// at run time and none where it is erased; one for every other value.
// Made of no type.
uint32_t componentCount(mlir::Type type);

// The words a value of `type` takes, as many as componentCount says, each
// with its kind, made of no type, so a data type asks them of its fields
// while it is being made; a data type's are the ones it computed then.
// Layouts::components makes their types.
llvm::SmallVector<families::SlotWord> slotWordsOf(mlir::Type type);

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

  // The runtime components of a value type.
  llvm::SmallVector<layout::Component> components(mlir::Type type) const;
  // The slots of `type`, a data type held in place.
  const layout::SumLayout &sum(DataType type) const;
  // The cells of `type`, a data type held in a cell, or a frame stack's
  // frames.
  const layout::CellLayout &cells(DataType type) const;
  // How a drop of a value of `type`, held in a cell or in place, claimed
  // `unique self` frees its fields: its field types are made here, since
  // no lowering worker makes a type.
  const layout::OwnCells &ownCells(DataType type) const;
  // The types of the fields of constructor `tag` of `type`, held in a cell
  // or in place, as its layout lays them out (tagsLaidOut, fieldsAt):
  // made here, since no lowering worker makes a type; none for a
  // constructor the type is not laid out over.
  llvm::ArrayRef<mlir::Type> fieldTypes(DataType type, Tag tag) const;
  // The most bytes of memory everything a value of `type` reaches takes,
  // its own cell included where it is held in one, where its type bounds
  // what it reaches (layout::reachOf): the largest over the constructors
  // its indices leave possible of the cell and what each field reaches, so
  // a refined value is bounded by its unrefined type's. Nothing for a
  // value whose type does not bound it. What a frame holding the value
  // past its last use holds of it, at most.
  std::optional<uint64_t> reachedBytes(mlir::Type type) const;
  // The bytes a component of type `component` takes, and the alignment it
  // takes them at, as the target lays it out: measured once, with the
  // layouts, for every component a layout holds, and where asked for any
  // other.
  unsigned sizeOf(mlir::Type component) const;
  unsigned alignmentOf(mlir::Type component) const;
  // The element layout of an array of `element`.
  layout::Element element(mlir::Type element) const;

  // The constructors a value of `type` is laid out over, and the field
  // types of constructor `tag` there: a closed application held in place
  // is its own unfolding, over the constructors its indices leave possible
  // at the fields they determine; any other value of a member is laid out
  // as the member at an unknown index, over every constructor at its own
  // fields, so all such applications of the member are the same words.
  // The second makes types: a lowering worker reads fieldTypes instead.
  static families::TagSet tagsLaidOut(DataType type);
  static llvm::SmallVector<mlir::Type> fieldsAt(DataType type, Tag tag);

private:
  // By declared tag, the types of each constructor's fields as the layout
  // lays them out; none for a constructor it is not laid out over.
  using FieldTypes = llvm::SmallVector<llvm::SmallVector<mlir::Type>>;

  // A data type held in place or in a cell, as the layouts hold it: its
  // field types, its slots or its cells, how a `unique self` drop frees its
  // fields, and the bytes everything a value of it reaches takes, none
  // where its type does not bound it.
  struct LaidOut {
    DataType type;
    FieldTypes fields;
    std::variant<layout::SumLayout, layout::CellLayout> shape;
    layout::OwnCells owned;
    std::optional<uint64_t> reached;
  };

  // The entry of `type`'s unrefined application; an internal error, saying
  // `what` was asked, for a type no value of the module held.
  const LaidOut &entryOf(DataType type, llvm::StringRef what) const;
  // The bytes each bounded type reaches, its fields' first, once every
  // entry's cells are laid out.
  void computeReach();
  static FieldTypes fieldTypesOf(DataType type);
  void record(mlir::Type component);
  // The cell of a constructor of `fieldTypes`, object slots first.
  layout::Cell cellOf(llvm::ArrayRef<llvm::SmallVector<layout::Component>> fields, Tag tag,
                      layout::GroupIn group, MemberKind kind) const;
  // The components of each of `fields`.
  llvm::SmallVector<llvm::SmallVector<layout::Component>>
  componentsOf(llvm::ArrayRef<mlir::Type> fields) const;
  layout::SumLayout sumOf(DataType type) const;
  layout::CellLayout cellsOf(DataType type, const FieldTypes &fields) const;
  layout::OwnCells ownCellsOf(DataType type, const FieldTypes &fields) const;

  mlir::Operation *root;
  // Each laid-out type, unrefined, numbered once in the order its layout
  // was computed, and its place: one lookup, then every fact one load. The
  // entries are sized by the program, in the footprint's storage.
  llvm::DenseMap<DataType, uint32_t> numbered;
  footprint::Vector<LaidOut> laidOut;
  llvm::DenseMap<mlir::Type, std::pair<unsigned, unsigned>> measures;
};

} // namespace idr

#endif // IDR_IR_LAYOUT_H
