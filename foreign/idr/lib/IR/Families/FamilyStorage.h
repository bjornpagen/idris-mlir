// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The storage of #idr.family, shared by the unit that makes it and the one
// that reads it: the group's members, which are its key, and what is derived
// of them when it is made.
#ifndef IDR_LIB_IR_FAMILIES_FAMILYSTORAGE_H
#define IDR_LIB_IR_FAMILIES_FAMILYSTORAGE_H

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/AttributeSupport.h"
#include "llvm/Support/Allocator.h"

#include <memory>

namespace idr::families::storage {

// Any member's constructors, in tag order, over the one view; a memo sum's
// states come from its storage.
llvm::SmallVector<CtorView> ctorsOf(const Member &member, llvm::ArrayRef<CtorView> states);
// A member's index sorts as declared: a frame stack's one natural.
llvm::ArrayRef<Sort> indicesOf(const Member &member);
MemberKind memberKindOf(const Member &member);

// Owns the arrays of members being built (read from bytecode, rebuilt
// with sub-elements replaced) until the family that copies them is made.
class Scratch {
public:
  template <typename T>
  llvm::MutableArrayRef<T> keep(llvm::ArrayRef<T> values) {
    T *out = arena.Allocate<T>(values.size());
    std::uninitialized_copy(values.begin(), values.end(), out);
    return llvm::MutableArrayRef<T>(out, values.size());
  }

private:
  llvm::BumpPtrAllocator arena;
};

} // namespace idr::families::storage

namespace idr::detail {

using families::CtorView;
using families::Descent;
using families::ListShape;
using families::Member;
using families::Shape;
using families::Sort;
using mlir::ArrayRef;

// What the storage derives of one member.
struct MemberFacts {
  Shape shape = Shape::Plain;
  std::optional<Descent> descent;
  std::optional<ListShape> list;
  Refs refsAtUnknown = Refs::Words;
  Reach reachAtUnknown = Reach::Bounded;
  // The members whose cells a `unique self` claim on this one covers: this
  // one first, then every member a field the claim reaches names,
  // recursively.
  ArrayRef<families::MemberRef> selfCells;
  // The member's index sorts: a frame stack's one natural, every other
  // member's declared.
  ArrayRef<Sort> indices;
  // The member's tags in the order of their labels, which the parser
  // searches.
  ArrayRef<Tag> byLabel;
  // A memo sum's two states, viewed as constructors.
  ArrayRef<CtorView> states;
};

struct FamilyAttrStorage : AttributeStorage {
  using KeyTy = ArrayRef<Member>;

  explicit FamilyAttrStorage(ArrayRef<Member> members) : members(members) {}

  bool operator==(const KeyTy &key) const { return key == members; }
  static llvm::hash_code hashKey(const KeyTy &key) { return llvm::hash_combine_range(key); }
  static FamilyAttrStorage *construct(AttributeStorageAllocator &allocator, const KeyTy &key);

  ArrayRef<Member> members;
  Containment containment = Containment::Acyclic;
  ArrayRef<MemberFacts> facts;
};

} // namespace idr::detail

#endif // IDR_LIB_IR_FAMILIES_FAMILYSTORAGE_H
