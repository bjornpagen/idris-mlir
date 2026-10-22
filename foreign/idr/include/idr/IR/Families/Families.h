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
// what idr.con builds and what idr.field reads is such a refined value. The
// refinement is normalized when the type is made: the constructors the
// indices exclude are dropped, a refinement to every constructor the
// indices allow is none, and binders the indices determine are not kept, so
// one value set has one type.
#ifndef IDR_IR_FAMILIES_FAMILIES_H
#define IDR_IR_FAMILIES_FAMILIES_H

#include "idr/IR/Families/Declaration.h"

#include "mlir/Bytecode/BytecodeImplementation.h"
#include "mlir/IR/AsmState.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/Sequence.h"

namespace idr {

class FamilyAttr;
class DataType;

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

// What a data type is at run time and what a value of it holds, computed
// once, when the type is made, from its declaration and indices
// (lib/IR/Layout/Classes.cpp): its class, its layout, and whether a value
// holds a reference a count accounts for.
struct LayoutFacts {
  Class cls;
  Layout layout;
  Refs refs;
  Reach reach;
  // The runtime components a value takes where it is held: a cell's
  // pointer and a number are one; a value in place, its tag (where two
  // constructors or more are possible) and its fields'; none where no
  // constructor is possible.
  uint32_t components;
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

// The class, layout and references of member `member` of `group` at the
// index terms `indices`: the class rule over plain arrays, so it runs inside
// the storage's construction, where no attribute or type may be made.
LayoutFacts classify(FamilyAttr group, uint32_t member, llvm::ArrayRef<TermNode> indices);

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

// Whether `type` names a closure or a suspension anywhere but inside a data
// type or a family, whose fields their declarations answer for
// (FamilyAttr::namesLabels): what exists only before idr-defunctionalize.
bool namesLabels(mlir::Type type);

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
// value's, as a case binds a pattern variable. None where the type fixes no
// constructor whose binders it determines, or that constructor has no field
// `index`. Every op that reads a field (idr.data.field, a cell's take and
// unpack) infers its result with it.
std::optional<mlir::Type> fieldReadType(mlir::Type value, unsigned index);

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
