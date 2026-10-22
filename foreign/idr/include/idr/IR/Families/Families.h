// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the C++ reads of a family and of a data type beyond the generated
// classes' own members (FamilyAttr, DataType, SelfType, SortsAttr, the
// specification's IdrisMLIR.Spec.Families.Dialect names each member a hand
// unit defines here): the set of constructors a type leaves possible, the
// facts a type computes when it is made, and the one way to read a
// constructor written by its label.
//
// A data type is `!idr.data<#F[ts]>`: a member of a group applied to index
// terms, perhaps refined to fewer constructors, `!idr.data<#List @Cons>`,
// `!idr.data<#T {@A, @B}>`, or, where a constructor binds an index variable
// its family's indices do not determine, to that constructor with its
// binders' terms, `!idr.data<#Ex @MkEx<v3>>`. What a case of a match binds,
// what idr.data.con builds and what idr.data.field reads is such a refined value. The
// refinement is normalized when the type is made: the constructors the
// indices exclude are dropped, a refinement to every constructor the
// indices allow is none, and binders the indices determine are not kept, so
// one value set has one type.

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
#include <variant>

namespace idr {

namespace families {

// The constructors a type leaves possible: every declared one, which a type
// at an index that excludes none and with no refinement has, or the ones
// its indices or its refinement leave, held in tag order.
class TagSet {
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
  auto at() const {
    return [copy = *this](size_t index) { return copy[index]; };
  }
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
// at the index terms `indices`, its words' arrays kept in `allocator`: the
// class rule over plain arrays, so it runs inside the storage's
// construction, where no attribute or type may be made.
LayoutFacts classify(FamilyAttr group, uint32_t member, llvm::ArrayRef<TermNode> indices,
                     mlir::StorageUniquer::StorageAllocator &allocator);

// The constructors of member `member` of `group` its index terms leave
// possible: each whose equation does not clash with them (unify, with the
// application's levels and the constructor's binders the unknowns).
llvm::SmallVector<Tag> possibleAt(FamilyAttr group, uint32_t member,
                                  llvm::ArrayRef<TermNode> indices);

// Reads a constructor's label into its tag in `group`, checking its arity:
// the one place a label becomes a tag.
mlir::ParseResult resolveLabel(mlir::AsmParser &parser, TermNode &node, FamilyAttr group,
                               llvm::StringRef label, llvm::SMLoc at);

// Whether a data type narrowed to fewer constructors counts as the same
// value: where a region binds a refined scrutinee or a cast forgets a
// refinement, yes; where a jump passes a parameter, no.
enum class Narrowing : uint8_t { Allowed, Exact };

// Whether a value of `from` and one of `to` are the same words at run time
// (DataType::layoutMatch, an array as its elements are): what decides
// whether a reindex between them is free or re-packs, and so the re-pack's
// effects. Makes no type.
LayoutMatch layoutMatch(mlir::Type from, mlir::Type to);

// Whether re-packing a value of `from` as one of `to` builds a cell or an
// array, so the result is a fresh value, counted and claimed unique, where
// any other reindex's memory is its operand's: never where the two are the
// same words, nor between two numbers (a numeral widened or narrowed);
// always into an array and into a value held as a cell; into a value held
// in place, where re-packing a field of a constructor both leave possible
// does. `fieldTypes(type, tag)` gives the types the fields of `tag` are
// laid out at: the layouts' stored ones on a lowering worker, which make no
// type, or Layouts::fieldsAt where a type may be made. The one answer the
// reindex's verifier and the lowering's re-pack read.
template <class FieldTypes>
  requires std::invocable<FieldTypes &, DataType, Tag>
bool builds(mlir::Type from, mlir::Type to, FieldTypes &&fieldTypes) {
  mlir::Type fromValue = unrestricted(from);
  mlir::Type toValue = unrestricted(to);
  if (layoutMatch(fromValue, toValue) == LayoutMatch::SameLayout)
    return false;
  if (llvm::isa<mlir::MemRefType>(toValue))
    return true;
  auto source = llvm::dyn_cast<DataType>(fromValue);
  auto target = llvm::dyn_cast<DataType>(toValue);
  if (!source || !target || isNumber(source.layout()))
    return false;
  if (target.layout() != Layout::InPlace)
    return true;
  for (Tag tag : source.possibleTags()) {
    if (!target.possibleTags().contains(tag))
      continue;
    auto sourceFields = fieldTypes(source, tag);
    auto targetFields = fieldTypes(target, tag);
    for (auto [a, z] : llvm::zip_equal(sourceFields, targetFields))
      if (builds(a, z, fieldTypes))
        return true;
  }
  return false;
}

// Whether a value of `type` can reach a closure or a suspension: one the
// type names itself, or one a data type it names reaches, which that type's
// family computed when it was made (FamilyAttr::closureReach), so nothing
// below a data type is walked. What exists only before idr-defunctionalize.
ClosureReach closureReach(mlir::Type type);

// Whether a value of `sub` stands where `super` is asked as the same value,
// with no op between: `sub` is `super` with its levels instantiated by one
// substitution (an index a case's equation fixes), at a data type perhaps
// refined to fewer constructors. What a match's region binds is such a
// refinement of what enters it. Context-free: every level of `super` may
// be instantiated, consistently, and an opaque index of `super` stands for
// any, one of `sub` for none `super` names; the exact substitution is the
// scope walk's to check.
bool refines(mlir::Type sub, mlir::Type super);

// Whether `instance` is `pattern` with its levels instantiated by one
// substitution: a jump's argument against its join region's parameter, a
// call's operand against its callee's. Context-free, as refines is.
bool instanceOf(mlir::Type instance, mlir::Type pattern);

} // namespace families

// The type at which field `index` of a value of type `value` is read: its
// carrier, at the value's uses times the field's, its hold read from the
// value's, as a case binds a pattern variable; a frame's field at the whole
// grade its declaration keeps the value at. None where the type fixes no
// constructor whose binders it determines, or that constructor has no field
// `index`. Every op that reads a field (idr.data.field, a cell's take and
// unpack) infers its result with it.
std::optional<mlir::Type> fieldReadType(mlir::Type value, unsigned index);

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
                      FamilyAttr group, uint64_t member, llvm::ArrayRef<families::TermNode> indices,
                      mlir::DenseI32ArrayAttr refinement,
                      llvm::ArrayRef<families::TermNode> binders);
SelfType readSelf(mlir::DialectBytecodeReader &reader, mlir::MLIRContext *context, uint64_t member,
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
