// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's types, and the storages of the families' two: the data
// type, a member of a family applied to index terms, perhaps refined to
// fewer constructors, and a member of a declaration's own group by
// position. A data type's storage is its content (the group, the member,
// the terms, the refinement), so equal types are one type and no table
// holds them; what the type is at run time and what a value of it holds are
// computed in its construction, over plain arrays and the storage of the
// types it names, which exist already, so nothing is made while a type is.
// A refinement is normalized by the builders (Families/DataNormal.cpp),
// never by the storage. Both storages are complete here, where the
// generated types are defined and registered.

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

namespace idr::detail {

// A data type's identity: the group, the member, the index terms, the
// constructors it is refined to, the tags ascending, uniqued as an array
// attribute (null: unrefined; empty: refined to no constructor, so no
// value has it), and the terms of the binders of its one constructor that
// its indices leave undetermined (none otherwise). A refined key carries
// its unrefined application too, made before the type is: a function of
// the rest, so no part of the identity, kept so a reader asks it of the
// storage and never of the type table.
struct DataKey {
  FamilyAttr group;
  uint32_t member;
  ArrayRef<TermNode> indices;
  DenseI32ArrayAttr refinement;
  ArrayRef<TermNode> binders;
  DataType base;

  bool operator==(const DataKey &other) const {
    return group == other.group && member == other.member && indices == other.indices &&
           refinement == other.refinement && binders == other.binders;
  }
};

// The parameters are the key; the rest is derived when the type is made.
struct DataTypeStorage : TypeStorage {
  using KeyTy = DataKey;

  DataTypeStorage(const KeyTy &key, TagSet possible, LayoutFacts facts, uint32_t freeLevels)
      : group(key.group), member(key.member), indices(key.indices), refinement(key.refinement),
        binders(key.binders), base(key.base), possible(possible), facts(facts),
        freeLevels(freeLevels) {}

  // The key of the parameters as the builders give them: a refined one's
  // unrefined application is made here, before the type, never while it
  // is being made.
  static KeyTy getKey(FamilyAttr group, uint64_t member, ArrayRef<TermNode> indices,
                      DenseI32ArrayAttr refinement, ArrayRef<TermNode> binders) {
    auto own = static_cast<uint32_t>(member);
    DataType base = refinement || !binders.empty()
                        ? DataType::get(group.getContext(), group, own, indices)
                        : DataType();
    return DataKey{group, own, indices, refinement, binders, base};
  }

  bool operator==(const KeyTy &other) const {
    return other == KeyTy{group, member, indices, refinement, binders};
  }
  // The parameters as MLIR walks and replaces them: a replacement rebuilds
  // the type through its builder.
  std::tuple<FamilyAttr, uint32_t, ArrayRef<TermNode>, DenseI32ArrayAttr, ArrayRef<TermNode>>
  getAsKey() const {
    return {group, member, indices, refinement, binders};
  }
  static llvm::hash_code hashKey(const KeyTy &key) {
    return llvm::hash_combine(
        key.group.getAsOpaquePointer(), key.member, llvm::hash_combine_range(key.indices),
        key.refinement.getAsOpaquePointer(), llvm::hash_combine_range(key.binders));
  }
  static DataTypeStorage *construct(TypeStorageAllocator &allocator, const KeyTy &key);

  FamilyAttr group;
  uint32_t member;
  ArrayRef<TermNode> indices;
  DenseI32ArrayAttr refinement;
  ArrayRef<TermNode> binders;
  // The unrefined application, null where this is it.
  DataType base;
  TagSet possible;
  LayoutFacts facts;
  uint32_t freeLevels;
};

// A member of the group being declared, and its indices over the
// constructor's binders.
struct SelfTypeStorage : TypeStorage {
  using KeyTy = std::tuple<uint64_t, ArrayRef<TermNode>>;

  SelfTypeStorage(uint64_t member, ArrayRef<TermNode> indices) : member(member), indices(indices) {}

  bool operator==(const KeyTy &key) const { return key == KeyTy(member, indices); }
  KeyTy getAsKey() const { return KeyTy(member, indices); }
  static llvm::hash_code hashKey(const KeyTy &key) {
    return llvm::hash_combine(std::get<0>(key), llvm::hash_combine_range(std::get<1>(key)));
  }
  static SelfTypeStorage *construct(TypeStorageAllocator &allocator, const KeyTy &key) {
    return new (allocator.allocate<SelfTypeStorage>())
        SelfTypeStorage(std::get<0>(key), allocator.copyInto(std::get<1>(key)));
  }

  uint64_t member;
  ArrayRef<TermNode> indices;
};

} // namespace idr::detail

idr::detail::DataTypeStorage *
idr::detail::DataTypeStorage::construct(TypeStorageAllocator &allocator, const KeyTy &key) {
  DataKey own{key.group,      key.member,
              allocator.copyInto(key.indices), key.refinement,
              allocator.copyInto(key.binders), key.base};
  uint32_t levels = std::max(freeLevelsOf(own.indices), freeLevelsOf(own.binders));
  // The layout is the unrefined application's: refining a value to fewer
  // constructors never changes how it is held, so a case's refined value
  // is the scrutinee itself, and its facts are read from that
  // application's storage rather than computed again.
  if (own.base) {
    const auto *base = static_cast<const DataTypeStorage *>(Type(own.base).getImpl());
    TagSet possible = base->possible;
    if (own.refinement) {
      SmallVector<Tag> tags = llvm::to_vector(llvm::map_range(
          own.refinement.asArrayRef(), [](int32_t tag) { return Tag{static_cast<uint32_t>(tag)}; }));
      possible = TagSet::listed(allocator.copyInto(ArrayRef<Tag>(tags)));
    }
    return new (allocator.allocate<DataTypeStorage>())
        DataTypeStorage(own, possible, base->facts, levels);
  }
  SmallVector<Tag> atIndices = possibleAt(own.group, own.member, own.indices);
  uint32_t declared = own.group.tagCount(own.member);
  TagSet possible = atIndices.size() == declared
                        ? TagSet::every(declared)
                        : TagSet::listed(allocator.copyInto(ArrayRef<Tag>(atIndices)));
  LayoutFacts facts = classify(own.group, own.member, own.indices, allocator);
  return new (allocator.allocate<DataTypeStorage>())
      DataTypeStorage(own, possible, facts, levels);
}

//===----------------------------------------------------------------------===//
// The generated types
//===----------------------------------------------------------------------===//

#define GET_TYPEDEF_CLASSES
#include "idr/IR/IdrTypes.cpp.inc"

#include "idr/IR/IdrTypeInterfaces.cpp.inc"

void IdrDialect::registerTypes() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "idr/IR/IdrTypes.cpp.inc"
      >();
  registerValueFacts();
}

//===----------------------------------------------------------------------===//
// The parameters, as the storages hold them
//===----------------------------------------------------------------------===//

FamilyAttr DataType::getGroup() const { return getImpl()->group; }
uint64_t DataType::getMember() const { return getImpl()->member; }
ArrayRef<TermNode> DataType::getIndices() const { return getImpl()->indices; }
DenseI32ArrayAttr DataType::getRefinement() const { return getImpl()->refinement; }
ArrayRef<TermNode> DataType::getBinders() const { return getImpl()->binders; }

uint64_t SelfType::getMember() const { return getImpl()->member; }
ArrayRef<TermNode> SelfType::getIndices() const { return getImpl()->indices; }

//===----------------------------------------------------------------------===//
// What a reader asks of a data type
//===----------------------------------------------------------------------===//

DataType DataType::get(MLIRContext *context, FamilyAttr group, uint32_t member,
                       ArrayRef<TermNode> indices) {
  return Base::get(context, idr::detail::DataKey{group, member, indices, {}, {}});
}

DataType DataType::unrefined() const {
  DataType base = getImpl()->base;
  return base ? base : *this;
}

const TagSet &DataType::possibleTags() const { return getImpl()->possible; }

std::optional<Tag> DataType::singleTag() const {
  if (possibleTags().size() != 1)
    return std::nullopt;
  return possibleTags().front();
}

uint32_t DataType::declaredCount() const { return getGroup().tagCount(getImpl()->member); }
MemberKind DataType::kind() const { return getGroup().memberKind(getImpl()->member); }
CtorView DataType::ctor(Tag tag) const { return getGroup().ctor(getImpl()->member, tag); }
ArrayRef<Sort> DataType::binderSorts(Tag tag) const { return ctor(tag).binders; }
std::optional<MemoView> DataType::memo() const { return getGroup().memo(getImpl()->member); }
std::optional<ClosuresView> DataType::closures() const {
  return getGroup().closures(getImpl()->member);
}
std::optional<ListShape> DataType::listShape() const {
  return getGroup().listShape(getImpl()->member);
}
Promise DataType::promise() const { return getGroup().promise(getImpl()->member); }

// What a value of a type rebuilt in place claims by its promise: its own
// cells unshared, whatever they hold. A claim on its own cells reaches the
// storage of every buffer one of them holds (fieldReach) and never the
// buffer's elements, so it is all a buffer written in place needs: a
// linear array of shared values keeps its promise, which a claim on what
// it reaches would refuse. A type with no promise claims nothing by it.
Unique DataType::promisedClaim() const {
  return promise() == Promise::InPlace ? Unique::Self : Unique::None;
}

FlatSymbolRefAttr DataType::labelFunction(Tag tag) const {
  return getGroup().labelFunction(getImpl()->member, tag);
}

std::optional<Mode> DataType::labelMode(Tag tag) const {
  return getGroup().labelMode(getImpl()->member, tag);
}

Layout DataType::layout() const { return getImpl()->facts.layout; }
Class DataType::cls() const { return getImpl()->facts.cls; }
uint32_t DataType::components() const { return getImpl()->facts.slots.count(); }
const Slots &DataType::slots() const { return getImpl()->facts.slots; }
std::optional<uint64_t> DataType::numeralBound() const { return getImpl()->facts.bound; }

// The same words where the two are one application, refinements aside; or
// numbers of one layout, each its layout's word; or two values of one
// member the layouts lay out as the member at an unknown index, which every
// cell, frame stack and value in place at an unknown class of it is, at its
// constructors' own fields, an array field's elements included, so the
// two share every word they reach. A closed application held in place is
// its own unfolding, so only that application has its words. Asked of
// every field a lowering worker reads, so it reads only the two types' own
// parameters and stored facts, and makes no type.
LayoutMatch DataType::layoutMatch(DataType other) const {
  if (getGroup() != other.getGroup() || getMember() != other.getMember())
    return LayoutMatch::OtherLayout;
  if (getIndices() == other.getIndices())
    return LayoutMatch::SameLayout;
  if (layout() != other.layout())
    return LayoutMatch::OtherLayout;
  auto unfolded = [](DataType type) {
    return type.layout() == Layout::InPlace && type.cls() == Class::Closed;
  };
  return unfolded(*this) || unfolded(other) ? LayoutMatch::OtherLayout : LayoutMatch::SameLayout;
}

bool DataType::boundsReach() const { return getImpl()->facts.reach == Reach::Bounded; }
ArrayRef<MemberRef> DataType::selfCells() const {
  return getGroup().selfCells(getImpl()->member);
}
uint32_t DataType::freeLevels() const { return getImpl()->freeLevels; }

// What a value of a data type holds, as its layout and facts say: a cell
// is one pointer to a cell, and a counted one; a value in place holds what
// its fields hold; a number of a fixed width holds nothing, a natural a
// big's word.
bool DataType::holdsReferences() const { return getImpl()->facts.refs == Refs::References; }
// A frame stack is pushed once and popped once: used once by its type, so
// no grade wraps it and no count is kept of it.
bool DataType::isLinearByType() const { return layout() == Layout::FrameStack; }
bool DataType::isCounted() const { return holdsReferences(); }
bool DataType::isCellPointer() const { return layout() == Layout::Cell; }
