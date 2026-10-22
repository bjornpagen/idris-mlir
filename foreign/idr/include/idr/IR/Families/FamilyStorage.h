// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The storages of the families' attributes, complete wherever the
// generated attribute classes are defined and registered: each keyed by its
// parameters, copied into the context once, and #idr.family keeping beside
// its key what is derived of its members when it is made: whether it holds
// itself, whether its values can reach a closure or a suspension, and each
// member's facts.
#ifndef IDR_IR_FAMILIES_FAMILYSTORAGE_H
#define IDR_IR_FAMILIES_FAMILYSTORAGE_H

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/AttributeSupport.h"
#include "llvm/Support/Allocator.h"

#include <memory>
#include <tuple>

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
using families::TermNode;
using mlir::ArrayRef;

// What the storage derives of one member.
struct MemberFacts {
  Shape shape = Shape::Plain;
  std::optional<Descent> descent;
  std::optional<ListShape> list;
  Refs refsAtUnknown = Refs::Words;
  Reach reachAtUnknown = Reach::Bounded;
  // Whether a cell the claim on this member's own cells covers holds a
  // buffer.
  Buffers buffers = Buffers::NoBuffer;
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

struct FamilyAttrStorage : mlir::AttributeStorage {
  using KeyTy = ArrayRef<Member>;

  explicit FamilyAttrStorage(ArrayRef<Member> members) : members(members) {}

  bool operator==(const KeyTy &key) const { return key == members; }
  static llvm::hash_code hashKey(const KeyTy &key) { return llvm::hash_combine_range(key); }
  static FamilyAttrStorage *construct(mlir::AttributeStorageAllocator &allocator,
                                      const KeyTy &key);

  ArrayRef<Member> members;
  families::Containment containment = families::Containment::Acyclic;
  ClosureReach closureReach = ClosureReach::NoClosure;
  ArrayRef<MemberFacts> facts;
};

// The sorts a scope binds.
struct IndexBindersAttrStorage : mlir::AttributeStorage {
  using KeyTy = ArrayRef<Sort>;

  explicit IndexBindersAttrStorage(ArrayRef<Sort> sorts) : sorts(sorts) {}

  bool operator==(const KeyTy &key) const { return key == sorts; }
  KeyTy getAsKey() const { return sorts; }
  static llvm::hash_code hashKey(const KeyTy &key) { return llvm::hash_combine_range(key); }
  static IndexBindersAttrStorage *construct(mlir::AttributeStorageAllocator &allocator,
                                            const KeyTy &key) {
    return new (allocator.allocate<IndexBindersAttrStorage>())
        IndexBindersAttrStorage(allocator.copyInto(key));
  }

  ArrayRef<Sort> sorts;
};

// The terms a call or a jump gives, one after the other, and how many.
struct IndexArgsAttrStorage : mlir::AttributeStorage {
  using KeyTy = std::tuple<ArrayRef<TermNode>, uint64_t>;

  IndexArgsAttrStorage(ArrayRef<TermNode> terms, uint64_t count) : terms(terms), count(count) {}

  bool operator==(const KeyTy &key) const { return key == KeyTy(terms, count); }
  KeyTy getAsKey() const { return KeyTy(terms, count); }
  static llvm::hash_code hashKey(const KeyTy &key) {
    return llvm::hash_combine(llvm::hash_combine_range(std::get<0>(key)), std::get<1>(key));
  }
  static IndexArgsAttrStorage *construct(mlir::AttributeStorageAllocator &allocator,
                                         const KeyTy &key) {
    return new (allocator.allocate<IndexArgsAttrStorage>())
        IndexArgsAttrStorage(allocator.copyInto(std::get<0>(key)), std::get<1>(key));
  }

  ArrayRef<TermNode> terms;
  uint64_t count;
};

// An assumed equality's two terms.
struct EquationAttrStorage : mlir::AttributeStorage {
  using KeyTy = std::tuple<ArrayRef<TermNode>, ArrayRef<TermNode>>;

  EquationAttrStorage(ArrayRef<TermNode> lhs, ArrayRef<TermNode> rhs) : lhs(lhs), rhs(rhs) {}

  bool operator==(const KeyTy &key) const { return key == KeyTy(lhs, rhs); }
  KeyTy getAsKey() const { return KeyTy(lhs, rhs); }
  static llvm::hash_code hashKey(const KeyTy &key) {
    return llvm::hash_combine(llvm::hash_combine_range(std::get<0>(key)),
                              llvm::hash_combine_range(std::get<1>(key)));
  }
  static EquationAttrStorage *construct(mlir::AttributeStorageAllocator &allocator,
                                        const KeyTy &key) {
    return new (allocator.allocate<EquationAttrStorage>()) EquationAttrStorage(
        allocator.copyInto(std::get<0>(key)), allocator.copyInto(std::get<1>(key)));
  }

  ArrayRef<TermNode> lhs, rhs;
};

// A constant constructor value: its refined data type, its cells, each an
// array of its fields, and the field its run runs along.
struct ConAttrStorage : mlir::AttributeStorage {
  using KeyTy = std::tuple<DataType, ArrayRef<mlir::Attribute>, uint64_t>;

  ConAttrStorage(DataType data, ArrayRef<mlir::Attribute> cells, uint64_t spine)
      : data(data), cells(cells), spine(spine) {}

  bool operator==(const KeyTy &key) const { return key == KeyTy(data, cells, spine); }
  KeyTy getAsKey() const { return KeyTy(data, cells, spine); }
  static llvm::hash_code hashKey(const KeyTy &key) {
    return llvm::hash_combine(std::get<0>(key).getAsOpaquePointer(),
                              llvm::hash_combine_range(std::get<1>(key)), std::get<2>(key));
  }
  static ConAttrStorage *construct(mlir::AttributeStorageAllocator &allocator, const KeyTy &key) {
    return new (allocator.allocate<ConAttrStorage>())
        ConAttrStorage(std::get<0>(key), allocator.copyInto(std::get<1>(key)), std::get<2>(key));
  }

  DataType data;
  ArrayRef<mlir::Attribute> cells;
  uint64_t spine;
};

} // namespace idr::detail

#endif // IDR_IR_FAMILIES_FAMILYSTORAGE_H
