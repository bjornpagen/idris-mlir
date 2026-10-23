// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's types, and the storages of the families' two: the data
// type, a member of a family applied to index terms, perhaps refined to
// fewer constructors, laid out as its indices say or open, and a member of
// a declaration's own group by position. A data type's storage is its
// content (the group, the member, the terms, the refinement, the mark), so
// equal types are one type and no table holds them; what the type is at run time and what a value of it holds are
// computed in its construction, over plain arrays and the storage of the
// types it names, which exist already, so nothing is made while a type is.
// A refinement is normalized by the builders (Families/DataNormal.cpp),
// never by the storage. Both storages are complete here, where the
// generated types are defined and registered.

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

#include <tuple>

using namespace mlir;
using namespace idr;
using namespace idr::families;

namespace idr::detail {

// A data type's identity: the group, the member, the index terms, the
// constructors it is refined to, the tags ascending, uniqued as an array
// attribute (null: unrefined; empty: refined to no constructor, so no
// value has it), the terms of the binders of its one constructor that its
// indices leave undetermined (none otherwise), and how its values are laid
// out. A refined key carries its unrefined application too, at the same
// mark, made before the type is: a function of the rest, so no part of the
// identity, kept so a reader asks it of the storage and never of the type
// table.
struct DataKey {
  FamilyAttr group;
  uint32_t member;
  ArrayRef<TermNode> indices;
  DenseI32ArrayAttr refinement;
  ArrayRef<TermNode> binders;
  LayoutMark mark;
  DataType base;

  // The parts that are the identity, which the base is a function of: what
  // the storage compares a key by.
  auto identity() const { return std::tie(group, member, indices, refinement, binders, mark); }
};

// The parameters are the key; the rest is derived when the type is made.
struct DataTypeStorage : TypeStorage {
  using KeyTy = DataKey;

  DataTypeStorage(const KeyTy &key, TagSet possible, LayoutFacts facts, uint32_t freeLevels)
      : group(key.group), member(key.member), indices(key.indices), refinement(key.refinement),
        binders(key.binders), mark(key.mark), base(key.base), possible(possible), facts(facts),
        freeLevels(freeLevels) {}

  // The key of the parameters as the builders give them: a refined one's
  // unrefined application is made here, before the type, never while it
  // is being made.
  static KeyTy getKey(FamilyAttr group, uint32_t member, ArrayRef<TermNode> indices,
                      DenseI32ArrayAttr refinement, ArrayRef<TermNode> binders, LayoutMark mark) {
    DataType base = refinement || !binders.empty()
                        ? DataType::get(group.getContext(), group, member, indices).marked(mark)
                        : DataType();
    return DataKey{group, member, indices, refinement, binders, mark, base};
  }

  bool operator==(const KeyTy &other) const { return other.identity() == getAsKey(); }
  // The parameters as MLIR walks and replaces them: a replacement rebuilds
  // the type through its builder.
  std::tuple<FamilyAttr, uint32_t, ArrayRef<TermNode>, DenseI32ArrayAttr, ArrayRef<TermNode>,
             LayoutMark>
  getAsKey() const {
    return {group, member, indices, refinement, binders, mark};
  }
  static llvm::hash_code hashKey(const KeyTy &key) {
    return llvm::hash_combine(key.group.getAsOpaquePointer(), key.member,
                              llvm::hash_combine_range(key.indices),
                              key.refinement.getAsOpaquePointer(),
                              llvm::hash_combine_range(key.binders), key.mark);
  }
  static DataTypeStorage *construct(TypeStorageAllocator &allocator, const KeyTy &key);

  FamilyAttr group;
  uint32_t member;
  ArrayRef<TermNode> indices;
  DenseI32ArrayAttr refinement;
  ArrayRef<TermNode> binders;
  LayoutMark mark;
  // The unrefined application, null where this is it.
  DataType base;
  TagSet possible;
  LayoutFacts facts;
  uint32_t freeLevels;
};

// A member of the group being declared, and its indices over the
// constructor's binders.
struct SelfTypeStorage : TypeStorage {
  using KeyTy = std::tuple<uint32_t, ArrayRef<TermNode>>;

  SelfTypeStorage(uint32_t member, ArrayRef<TermNode> indices) : member(member), indices(indices) {}

  bool operator==(const KeyTy &key) const { return key == KeyTy(member, indices); }
  KeyTy getAsKey() const { return KeyTy(member, indices); }
  static llvm::hash_code hashKey(const KeyTy &key) {
    return llvm::hash_combine(std::get<0>(key), llvm::hash_combine_range(std::get<1>(key)));
  }
  static SelfTypeStorage *construct(TypeStorageAllocator &allocator, const KeyTy &key) {
    return new (allocator.allocate<SelfTypeStorage>())
        SelfTypeStorage(std::get<0>(key), allocator.copyInto(std::get<1>(key)));
  }

  uint32_t member;
  ArrayRef<TermNode> indices;
};

} // namespace idr::detail

idr::detail::DataTypeStorage *
idr::detail::DataTypeStorage::construct(TypeStorageAllocator &allocator, const KeyTy &key) {
  DataKey own{key.group,      key.member,
              allocator.copyInto(key.indices), key.refinement,
              allocator.copyInto(key.binders), key.mark, key.base};
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
  LayoutFacts facts = classify(own.group, own.member, own.indices, own.mark, allocator);
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
uint32_t DataType::getMember() const { return getImpl()->member; }
ArrayRef<TermNode> DataType::getIndices() const { return getImpl()->indices; }
DenseI32ArrayAttr DataType::getRefinement() const { return getImpl()->refinement; }
ArrayRef<TermNode> DataType::getBinders() const { return getImpl()->binders; }
LayoutMark DataType::getMark() const { return getImpl()->mark; }

uint32_t SelfType::getMember() const { return getImpl()->member; }
ArrayRef<TermNode> SelfType::getIndices() const { return getImpl()->indices; }

//===----------------------------------------------------------------------===//
// What a reader asks of a data type
//===----------------------------------------------------------------------===//

// Through the parameters, as every builder passes them: upstream checks the
// type's invariants on them, and the storage makes its key from them. A
// type is made laid out as its indices say; only `marked` opens one.
DataType DataType::get(MLIRContext *context, FamilyAttr group, uint32_t member,
                       ArrayRef<TermNode> indices) {
  return Base::get(context, group, member, indices, DenseI32ArrayAttr(), ArrayRef<TermNode>(),
                   LayoutMark::ByIndices);
}

// The same type, its refinement and binders kept, laid out as `mark` says.
DataType DataType::marked(LayoutMark mark) const {
  return Base::get(getContext(), getGroup(), getMember(), getIndices(), getRefinement(),
                   getBinders(), mark);
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

// How far a value's claim on its own cells reaches into a field of a data
// type: into the cells of a family rebuilt in place, which are the value's
// own by its promise; never into another family's.
FieldReach DataType::getFieldReach() const {
  return promise() == Promise::InPlace ? FieldReach::InPlaceFamily : FieldReach::Other;
}

// A field of a member of the group being declared is a cell of the value's
// own family, which its claim on its own cells covers.
FieldReach SelfType::getFieldReach() const { return FieldReach::OwnFamily; }

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
// no grade wraps it and no count is kept of it. Any other data is used as
// its grade says.
ByType DataType::getByType() const {
  return layout() == Layout::FrameStack ? ByType::UsedOnceByType : ByType::UsedAsGraded;
}
bool DataType::isCounted() const { return holdsReferences(); }
bool DataType::isCellPointer() const { return layout() == Layout::Cell; }
// At run time a data type is the words it computed when it was made. Its
// values carry no label of their own: a closure a field holds is the
// field's, an anchor of its own; they carry a counted reference where they
// hold one. A value is no cell's memory, which counting makes beside it.
RunTimeWords DataType::getRunTimeWords(std::optional<Hold>) const {
  return run_time_words::Held{{*this}};
}
Carrying DataType::getCarrying() const {
  return holdsReferences() ? Carrying(carrying::Reference{}) : Carrying(carrying::Nothing{});
}
bool DataType::isCellMemory() const { return false; }

// A numeral whose indices fix its bound is a word of its layout's width,
// read as its bits; one whose index is open is laid out as a natural, and
// read as one. Any other data holds no number, and is read as its bits.
NumericReading DataType::getNumericReading() const {
  return !numeralBound() && layout() == Layout::Natural ? NumericReading::Natural
                                                        : NumericReading::Bits;
}

// A numeral laid out as a natural is a big's word at run time, but no
// Integer the big ops take: its constant is a constructor, never a
// #idr.big, and it is narrowed as data, not as a big.
bool DataType::isCarriedAsBig() const { return false; }
