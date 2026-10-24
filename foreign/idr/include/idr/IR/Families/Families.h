// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the C++ reads of a family and of a data type beyond the generated
// classes' own members (FamilyAttr, DataType, SelfType, SortsAttr, the
// specification's IdrisMLIR.Spec.Families.Dialect names each member a hand
// unit defines here): the set of constructors a type leaves possible, the
// facts a type computes when it is made, and the one way to read a
// constructor written by its label; and what the op interfaces after it
// name of index terms and layouts: what a region assumes as it is entered,
// and the module's layouts by name.
//
// A data type is `!idr.data<#F[ts]>`: a member of a group applied to index
// terms, perhaps refined to fewer constructors, `!idr.data<#List @Cons>`,
// `!idr.data<#T {@A, @B}>`, or, where a constructor binds an index variable
// its family's indices do not determine, to that constructor with its
// binders' terms, `!idr.data<#Ex @MkEx<v3>>`. What a case of a match binds,
// what idr.data.con builds and what idr.data.field reads is such a refined value. The
// refinement is normalized when the type is made: the constructors the
// indices exclude are dropped, a refinement to every constructor the
// indices allow is none unless it keeps a constructor's binders' terms, and
// binders the indices determine are not kept, so one value set has one
// type.

// This header is the part of the dialect's header that follows the
// generated classes, which its declarations and ConAttr's walk name. A unit
// that includes it first is handed the dialect's header, which includes
// this one in its place; so the include stands outside the guard.
#include "idr/IR/IdrDialect.h"

#ifndef IDR_IR_FAMILIES_FAMILIES_H
#define IDR_IR_FAMILIES_FAMILIES_H

#include "idr/IR/Families/Declaration.h"
// Whether a value holds references (Refs), the grade's fact of a carrier,
// which a type's facts below hold.
#include "idr/IR/Grades.h"

// The kinds of word a runtime component is, which a type's words hold.
#include "idr/IR/Generated/Words.h.inc"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "mlir/IR/AsmState.h"
#include "mlir/IR/OpImplementation.h"
#include "mlir/Support/StorageUniquer.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"

#include <concepts>
#include <utility>
#include <variant>

namespace idr {

// The layouts of a module's values, which an op interface reads by
// reference (the bytes a put takes): its name is enough here, and its
// definition (Layout.h) needs the dialect's ops, so it follows them.
class Layouts;

namespace families {

// The constructors a type leaves possible: every declared one, which a type
// at an index that excludes none and with no refinement has, or the ones
// its indices or its refinement leave, held in tag order.
class TagSet {
  // The tag at each position, over a copy of the set, which the iterators
  // map positions through. Defined ahead of begin and end, which deduce
  // their type from it.
  auto at() const {
    return [copy = *this](size_t index) { return copy[index]; };
  }

public:
  static TagSet every(uint32_t declared) { return TagSet(declared, {}); }
  static TagSet listed(llvm::ArrayRef<Tag> tags) { return TagSet(0, tags); }

  size_t size() const { return all > 0 ? all : listed_.size(); }
  bool empty() const { return size() == 0; }
  Tag front() const { return (*this)[0]; }
  Tag operator[](size_t index) const {
    return all > 0 ? Tag{static_cast<uint32_t>(index)} : listed_[index];
  }
  bool contains(Tag tag) const;
  // Whether every tag of `other` is one of these.
  bool includes(const TagSet &other) const;

  auto begin() const { return llvm::map_range(llvm::seq<size_t>(0, size()), at()).begin(); }
  auto end() const { return llvm::map_range(llvm::seq<size_t>(0, size()), at()).end(); }

private:
  TagSet(uint32_t all, llvm::ArrayRef<Tag> listed) : all(all), listed_(listed) {}
  uint32_t all;
  llvm::ArrayRef<Tag> listed_;
};

// One run-time word of a value, made of no MLIR type, so a data type lays
// out its words while it is being made: a pointer of the target, an
// integer of a width, or a builtin scalar the value is itself; and the
// kind of word it is, which decides how a count is kept of it.
struct PointerWord {
  bool operator==(const PointerWord &) const = default;
};
struct IntegerWord {
  unsigned bits;
  bool operator==(const IntegerWord &) const = default;
};
struct ScalarWord {
  mlir::Type type;
  bool operator==(const ScalarWord &) const = default;
};
struct SlotWord {
  std::variant<PointerWord, IntegerWord, ScalarWord> shape;
  layout::Word kind;
  bool operator==(const SlotWord &) const = default;
};

// The words a value of a data type takes where it is held, computed once
// when the type is made: a cell's pointer, a frame stack's top or a
// number's word; or, held in place, the tag where it is laid out over two
// constructors or more, then the words its constructors' fields take, two
// constructors sharing a word of one shape and kind. For each declared
// constructor a value in place is laid out over, by tag, each field's
// words, as positions among all of them, the tag's included; nothing for
// any other constructor, and nothing at all for a value held as one word,
// whose fields are in its cell. Its count is every reader's: how many
// runtime components the value takes.
struct Slots {
  std::optional<IntegerWord> tag;
  llvm::ArrayRef<SlotWord> words;
  llvm::ArrayRef<llvm::ArrayRef<llvm::ArrayRef<uint32_t>>> fields;

  uint32_t count() const { return (tag ? 1u : 0u) + static_cast<uint32_t>(words.size()); }
};

// What a data type is at run time and what a value of it holds, computed
// once, when the type is made, from its declaration and indices
// (lib/IR/Layout/Classes.cpp): its class, its layout, whether a value holds
// a reference a count accounts for, and its words.
struct LayoutFacts {
  Class cls;
  Layout layout;
  Refs refs;
  Reach reach;
  // A numeral's largest value, the bound its closed indices fix, which
  // chose its width: written with a fixed-width layout, by the one rule
  // that picks the width from it, and with no other.
  std::optional<uint64_t> bound;
  Slots slots;
};

// Whether a layout is a number: one of the fixed widths or a natural. A
// frame stack is none of the others: linear by its type, never counted.
constexpr bool isNumber(Layout layout) {
  return layout == Layout::Word8 || layout == Layout::Word16 || layout == Layout::Word32 ||
         layout == Layout::Word64 || layout == Layout::Natural;
}

// The width in bits of a fixed-width number's layout; a natural's word is
// 64 bits too, a big's.
constexpr unsigned numberBits(Layout layout) {
  return layout == Layout::Word8 ? 8u : layout == Layout::Word16 ? 16u : layout == Layout::Word32 ? 32u : 64u;
}

// The class, layout, references and words of member `member` of `group`
// at the index terms `indices`, laid out as `mark` says, its words' arrays
// kept in `allocator`: the class rule over plain arrays, so it runs inside
// the storage's construction, where no attribute or type may be made.
LayoutFacts classify(FamilyAttr group, uint32_t member, llvm::ArrayRef<TermNode> indices,
                     LayoutMark mark, mlir::StorageUniquer::StorageAllocator &allocator);

// Whether a closed application's unfolding is the class rule's to run, or
// one a value in place that holds it already ran: a value unfolded within
// the budget unfolded every closed application among its fields within
// what it left and met no cycle through any, so each is in place by its own
// unfolding unless its kind or shape fixes its layout.
enum class Unfolding : uint8_t { Run, ByHolder };

// The class and layout the class rule gives member `member` of `group` at
// `indices`, laid out as `mark` says, keeping no word: classify's, for an
// application no type was made for, a field at the terms its holder's
// substitution writes. Makes no type.
std::pair<Class, Layout> classAt(FamilyAttr group, uint32_t member,
                                 llvm::ArrayRef<TermNode> indices, LayoutMark mark,
                                 Unfolding unfolding);

// The constructors of member `member` of `group` its index terms leave
// possible: each whose equation does not clash with them (unify, with the
// application's levels and the constructor's binders the unknowns).
llvm::SmallVector<Tag> possibleAt(FamilyAttr group, uint32_t member,
                                  llvm::ArrayRef<TermNode> indices);

// The terms constructor `tag`'s binders take where member `member` of
// `group`, at the closed `indices`, lays the constructor's fields out as
// its own unfolding: each binder the indices solve its term, one-way, and
// each they leave open itself, the constructor's own. So a field naming
// only solved binders is at closed terms and one naming an open binder at
// an index no unfolding closes, as the class rule laid each out when the
// application's type was made. A constructor the indices leave possible.
llvm::SmallVector<TermNode> solvedBinders(FamilyAttr group, uint32_t member,
                                          llvm::ArrayRef<TermNode> indices, Tag tag);

// A field's type that names a member of the group the field is declared in
// by position: no type was made for that application, so where its terms
// are not closed its facts are its member's at an unknown index.
struct ByPosition {};

// The application a field's declared type names over its constructor's
// binders: a member of the group the field is declared in, named by
// position, at the one run of terms it names, laid out by them; or the
// member of its own group a data type names, at its terms, laid out as its
// mark says. And where the declared type's facts come from: none was made
// for a member named by position; a data type stored its own when it was
// made. The class rule's unfolding and a re-pack's walk read each field
// through it.
struct NamedApplication {
  FamilyAttr group;
  uint32_t member;
  llvm::ArrayRef<TermNode> terms;
  LayoutMark mark;
  std::variant<ByPosition, DataType> declared;

  // The constructors the declared type keeps: those a data type's
  // refinement keeps, else every one its member declares.
  TagSet kept() const;
};

// What `field`, the value type of a field declared in a member of `holder`,
// names; none for any other type, whose words no index decides. Asked of
// the index interface, which says what a field of each type names.
std::optional<NamedApplication> namedBy(FamilyAttr holder, mlir::Type field);

// Reads a constructor's label into its tag in `group`, checking its arity:
// the one place a label becomes a tag.
mlir::ParseResult resolveLabel(mlir::AsmParser &parser, TermNode &node, FamilyAttr group,
                               llvm::StringRef label, llvm::SMLoc at);

// Which of the two relations a match checks. A refinement, where a region
// binds a refined scrutinee or a cast forgets a refinement, counts a data
// type narrowed to fewer constructors as the same value and takes an index
// the language cannot write for the term the other type names there; an
// instance, where a jump passes a parameter, does neither.
enum class Narrowing : uint8_t { Allowed, Exact };

// A member applied to index terms as layoutMatch compares two: its terms
// and its mark, and the class and layout the class rule gives it. A data
// type's are its own and those it stored when it was made (placedOf); a
// field's in a re-pack's walk are the terms its holder's substitution
// writes and the facts classAt gives them, so no type is made for it.
struct Placed {
  FamilyAttr group;
  uint32_t member;
  llvm::ArrayRef<TermNode> indices;
  LayoutMark mark;
  Class cls;
  Layout layout;
};

Placed placedOf(DataType type);

// Whether a value of `from` and one of `to` are the same words at run time:
// two applications by their placements, an array, a tensor or a memref
// alike, as its elements are, any other two where their words agree. What
// decides whether a reindex between them is free or re-packs, and so the
// re-pack's effects. Makes no type.
LayoutMatch layoutMatch(mlir::Type from, mlir::Type to);
LayoutMatch layoutMatch(const Placed &from, const Placed &to);

// Whether re-packing a value of `from` as one of `to` builds a cell or an
// array, so the result is a fresh value, counted and claimed unique, where
// any other reindex's memory is its operand's: decided from what the two
// types stored when they were made and from their index terms, as the class
// rule decides a class, down the fields of the values held in place, each
// at the terms its holder's substitution writes. A tensor is a value with
// no memory of its own, so re-packing its elements builds nothing here: the
// fresh array is its buffer's, which bufferization makes where it puts the
// re-pack. Makes no type or attribute, so a lowering worker asks it as the
// reindex's verifier and its flow do: the one answer all of them read.
bool builds(mlir::Type from, mlir::Type to);

// The hold of what a re-pack that builds gives, at `uses`: a fresh value,
// so freed by its count and claiming its own cells unshared whatever its
// operand's hold, where its uses let it claim them before references are
// counted (the grade's uncountedClaims: one used many times claims
// nothing); `stated`, the claim its type states, where that claims more.
// The one rule the reindex's verifier holds a building reindex to and every
// builder of one writes.
Hold builtHold(Uses uses, Unique stated);

// The value of `numeral`, a constant of a family of numeral shape: the
// number of its successor's layers, read off its run of cells.
uint64_t numeralValue(ConAttr numeral);

// Whether reading field `index` of a value of `container`, refined to one
// constructor, re-packs its slot (the field as the container's layout lays
// it out) into the field at the constructor's binders the read's type
// states by building a cell or an array, so the read gives a fresh value;
// false where the container gives no such read. The same walk as builds,
// making no type.
bool fieldReadBuilds(mlir::Type container, unsigned index);

// Whether a value of `type` can reach a closure or a suspension: one the
// type names itself, or one a data type it names reaches, which that type's
// family computed when it was made (FamilyAttr::closureReach), so nothing
// below a data type is walked. What exists only before idr-defunctionalize.
ClosureReach closureReach(mlir::Type type);

// Whether `sub` refines `super`: it is `super` with its levels instantiated
// by one substitution (an index a case's equation fixes), at a data type
// perhaps refined to fewer constructors. What a match's region binds is
// such a refinement of what enters it. Context-free: every level of
// `super` may be instantiated, consistently; an opaque index of `super`
// stands for any, and a term of `sub` holding one, an index Idris proved
// and the language cannot write, is taken for `super`'s term there
// (PatternMatch::readInstance), so a cast from one is admitted to a closed
// term as to a level and substitution never changes what verifies; the
// exact substitution is the scope walk's to check. A layout mark is no index:
// two types that differ in theirs alone refine each other, and whether a
// value of one is the same words as one of the other is layoutMatch's.
bool refines(mlir::Type sub, mlir::Type super);

// Whether `instance` is `pattern` with its levels instantiated by one
// substitution: a jump's argument against its join region's parameter, a
// call's operand against its callee's. Context-free, as refines is, but an
// opaque index of `instance` is no index `pattern` names: it meets only an
// opaque term or a free level.
bool instanceOf(mlir::Type instance, mlir::Type pattern);

// Whose levels an equation's right side names: the binders the region
// itself binds (a case's constructor's), or the enclosing scope's (an
// assumed equality).
enum class Scoped : uint8_t { RegionBinders, Enclosing };

// What a region assumes as it is entered: `count` terms of the enclosing
// scope equal, one by one, to `count` terms of `inner`'s scope; `group` the
// family a null group in a term names. The binder interface returns it, so
// it is declared here, ahead of the interfaces; the scope walk that reads it
// is Scope.h's.
struct RegionRefinement {
  llvm::ArrayRef<TermNode> outer;
  llvm::ArrayRef<TermNode> inner;
  size_t count;
  Scoped scope;
  FamilyAttr group;
};

} // namespace families

// The type at which field `index` of a value of type `value` is read: its
// carrier, at the value's uses times the field's, its hold read from the
// value's, as a case binds a pattern variable; a frame's field at the whole
// grade its declaration keeps the value at. None where the type fixes no
// constructor whose binders it determines, or that constructor has no field
// `index`. Every op that reads a field (idr.data.field, a cell's take and
// unpack) infers its result with it.
std::optional<mlir::Type> fieldReadType(mlir::Type value, unsigned index);

// The array field `index` of a value of type `value` holds as its buffer,
// opened: the tensor of the buffer's shape and element, whatever grade a
// read gives the buffer. None where the field holds no value array's
// buffer. Every op that opens the array a field holds (idr.array.open, the
// take before bufferization) infers it with this.
std::optional<mlir::RankedTensorType> openedArrayType(mlir::Type value, unsigned index);

// Each field of a constructor constant with its position in the
// constructor, cell by cell along the run, each cell's fields read where
// the cell holds them. The step is a template parameter, so each walk's is
// inlined where it is written.
template <::std::invocable<::mlir::Attribute, unsigned> Each>
void ConAttr::walkFields(Each &&each) const {
  for (auto [cell, fields] : llvm::enumerate(getCells()))
    for (auto [position, field] : llvm::enumerate(mlir::cast<mlir::ArrayAttr>(fields)))
      each(field, fieldOfCell(static_cast<unsigned>(cell), static_cast<unsigned>(position)));
}

// The builders the dialect's bytecode reader calls once it has read a
// type's or an attribute's parameters: each checks what was read, as the
// text parser does, and makes it in normal form; null, after an error on
// `reader`, for what no type or attribute is.
FamilyAttr readFamily(mlir::DialectBytecodeReader &reader, mlir::MLIRContext *context,
                      llvm::ArrayRef<families::Member> members);
DataType readDataType(mlir::DialectBytecodeReader &reader, mlir::MLIRContext *context,
                      FamilyAttr group, uint32_t member, llvm::ArrayRef<families::TermNode> indices,
                      mlir::DenseI32ArrayAttr refinement,
                      llvm::ArrayRef<families::TermNode> binders, LayoutMark mark);
SelfType readSelf(mlir::DialectBytecodeReader &reader, mlir::MLIRContext *context, uint32_t member,
                  llvm::ArrayRef<families::TermNode> indices);
IndexBindersAttr readIndexBinders(mlir::DialectBytecodeReader &reader, mlir::MLIRContext *context,
                                  llvm::ArrayRef<families::Sort> sorts);
IndexArgsAttr readIndexArgs(mlir::DialectBytecodeReader &reader, mlir::MLIRContext *context,
                            llvm::ArrayRef<families::TermNode> terms, uint64_t count);
EquationAttr readEquation(mlir::DialectBytecodeReader &reader, mlir::MLIRContext *context,
                          llvm::ArrayRef<families::TermNode> lhs,
                          llvm::ArrayRef<families::TermNode> rhs);
ConAttr readCon(mlir::DialectBytecodeReader &reader, mlir::MLIRContext *context, DataType data,
                llvm::ArrayRef<mlir::Attribute> cells, uint64_t spine);

} // namespace idr

#endif // IDR_IR_FAMILIES_FAMILIES_H
