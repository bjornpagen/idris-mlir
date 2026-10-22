// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The dialect's types, and the data type: a member of a family applied to
// index terms, perhaps refined to fewer constructors. Its storage is its
// content (the group, the member, the terms, the refinement), so equal
// types are one type and no table holds them; what the type is at run time
// and what a value of it holds are computed in its construction, over plain
// arrays and the storage of the types it names, which exist already, so
// nothing is made while a type is. A refinement is normalized by the
// builders, never by the storage: the constructors the indices exclude are
// dropped, a refinement to every constructor the indices allow is none, and
// binders the indices determine are not kept.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Unify.h"
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
// its indices leave undetermined (none otherwise).
struct DataKey {
  FamilyAttr group;
  uint32_t member;
  ArrayRef<TermNode> indices;
  DenseI32ArrayAttr refinement;
  ArrayRef<TermNode> binders;

  bool operator==(const DataKey &) const = default;
};

// The parameters are the key, each a field of its own name, which the
// generated accessors read; the rest is derived when the type is made.
struct DataTypeStorage : TypeStorage {
  using KeyTy = DataKey;

  DataTypeStorage(const KeyTy &key, TagSet possible, LayoutFacts facts, uint32_t freeLevels)
      : group(key.group), member(key.member), indices(key.indices), refinement(key.refinement),
        binders(key.binders), possible(possible), facts(facts), freeLevels(freeLevels) {}

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
  TagSet possible;
  LayoutFacts facts;
  uint32_t freeLevels;
};

} // namespace idr::detail

idr::detail::DataTypeStorage *
idr::detail::DataTypeStorage::construct(TypeStorageAllocator &allocator, const KeyTy &key) {
  DataKey own{key.group, key.member, allocator.copyInto(key.indices), key.refinement,
              allocator.copyInto(key.binders)};
  SmallVector<Tag> atIndices = possibleAt(own.group, own.member, own.indices);
  uint32_t declared = own.group.tagCount(own.member);
  // The layout is the unrefined application's: refining a value to fewer
  // constructors never changes how it is held, so a case's refined value
  // is the scrutinee itself.
  TagSet unrefined = atIndices.size() == declared
                         ? TagSet::every(declared)
                         : TagSet::listed(allocator.copyInto(ArrayRef<Tag>(atIndices)));
  LayoutFacts facts = classify(own.group, own.member, own.indices);
  TagSet possible = unrefined;
  if (own.refinement) {
    SmallVector<Tag> tags = llvm::to_vector(llvm::map_range(
        own.refinement.asArrayRef(), [](int32_t tag) { return Tag{static_cast<uint32_t>(tag)}; }));
    possible = TagSet::listed(allocator.copyInto(ArrayRef<Tag>(tags)));
  }
  uint32_t levels = std::max(freeLevelsOf(own.indices), freeLevelsOf(own.binders));
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
// Making a data type
//===----------------------------------------------------------------------===//

namespace {

// The terms of constructor `tag`'s binders its application's indices
// determine: one-way, the binders the unknowns and the application's
// levels rigid. None where one stays unbound.
std::optional<SmallVector<TermNode>> determined(FamilyAttr group, uint32_t member,
                                                ArrayRef<TermNode> indices, Tag tag) {
  CtorView ctor = group.ctor(member, tag);
  size_t count = group.indices(member).size();
  Subst subst(freeLevelsOf(indices), static_cast<uint32_t>(ctor.binders.size()), Freedom::Rigid,
              Freedom::Unknown, Opacity::MeetsAnything, group);
  if (unifyAll(subst, indices, ctor.equation, count) == Unified::Clash)
    return std::nullopt;
  SmallVector<TermNode> out;
  TermWriter write(out);
  TermNode level{TermKind::Level, 0, 0, 0, Attribute()};
  for (uint32_t binder = 0; binder < ctor.binders.size(); ++binder) {
    level.value = binder;
    if (subst.write(write, Term(ArrayRef<TermNode>(level)), Side::Constructor, 0) ==
        Instance::Undetermined)
      return std::nullopt;
  }
  return out;
}

} // namespace

DataType DataType::get(MLIRContext *context, FamilyAttr group, uint32_t member,
                       ArrayRef<TermNode> indices) {
  return Base::get(context, idr::detail::DataKey{group, member, indices, {}, {}});
}

namespace {

// Tags as the refinement holds them.
DenseI32ArrayAttr tagsAttr(MLIRContext *context, ArrayRef<Tag> tags) {
  SmallVector<int32_t> numbers = llvm::to_vector(
      llvm::map_range(tags, [](Tag tag) { return static_cast<int32_t>(tag); }));
  return DenseI32ArrayAttr::get(context, numbers);
}

} // namespace

DataType DataType::unrefined() const {
  return get(getContext(), getGroup(), getMember(), getIndices());
}

// The constructors of `tags` this type and its indices leave possible: none
// of them makes the type uninhabited, all of them leaves it unrefined.
DataType DataType::refined(ArrayRef<Tag> tags) const {
  DataType base = unrefined();
  SmallVector<Tag> kept;
  for (Tag tag : base.possibleTags())
    if (llvm::is_contained(tags, tag) && possibleTags().contains(tag))
      kept.push_back(tag);
  if (kept.size() == base.possibleTags().size())
    return base;
  return Base::get(getContext(), idr::detail::DataKey{getGroup(), getMember(), getIndices(),
                                                      tagsAttr(getContext(), kept), {}});
}

DataType DataType::refinedTo(Tag tag, ArrayRef<TermNode> binders) const {
  DataType one = refined({tag});
  if (binders.empty() || !one.singleTag() ||
      determined(getGroup(), getMember(), getIndices(), tag))
    return one;
  return Base::get(getContext(), idr::detail::DataKey{getGroup(), getMember(), getIndices(),
                                                      tagsAttr(getContext(), {tag}), binders});
}

namespace {

// What every builder from parts no builder of ours made checks first: a
// member of the family, one whole term per index, refined tags the member
// declares, and binders' terms, whole, one per binder of the one
// constructor a refinement names. The tags as read, ascending and once
// each; none where the type is unrefined.
FailureOr<std::optional<SmallVector<Tag>>>
checkParts(function_ref<InFlightDiagnostic()> emitError, FamilyAttr group, uint64_t member,
           ArrayRef<TermNode> indices, DenseI32ArrayAttr refinement, ArrayRef<TermNode> binders) {
  if (!group || member >= group.getMembers().size())
    return emitError() << "expects a member of the family";
  auto at = static_cast<uint32_t>(member);
  if (countTerms(indices) != group.indices(at).size())
    return emitError() << "expects " << group.indices(at).size() << " whole index terms";
  std::optional<SmallVector<Tag>> tags;
  if (refinement) {
    tags.emplace();
    for (int32_t number : refinement.asArrayRef()) {
      if (number < 0 || static_cast<uint32_t>(number) >= group.tagCount(at))
        return emitError() << "is refined to a constructor its family does not declare";
      tags->push_back(Tag{static_cast<uint32_t>(number)});
    }
    llvm::sort(*tags);
    tags->erase(std::unique(tags->begin(), tags->end()), tags->end());
  }
  if (!binders.empty()) {
    size_t expected = tags && tags->size() == 1 ? group.ctor(at, tags->front()).binders.size() : 0;
    if (expected == 0 || countTerms(binders) != expected)
      return emitError() << "gives binders' terms to no one constructor, or not one per binder";
  }
  return tags;
}

} // namespace

// A type as its builders make it, its one spelling: what it was checked
// for, and its refinement in normal form, ascending, to constructors its
// indices leave possible and fewer than all of them, its binders kept only
// where the indices leave them undetermined.
LogicalResult DataType::verify(function_ref<InFlightDiagnostic()> emitError, FamilyAttr group,
                               uint64_t member, ArrayRef<TermNode> indices,
                               DenseI32ArrayAttr refinement, ArrayRef<TermNode> binders) {
  FailureOr<std::optional<SmallVector<Tag>>> tags =
      checkParts(emitError, group, member, indices, refinement, binders);
  if (failed(tags))
    return failure();
  if (!*tags)
    return success();
  auto at = static_cast<uint32_t>(member);
  SmallVector<Tag> possible = possibleAt(group, at, indices);
  if ((*tags)->size() != refinement.size() ||
      !llvm::all_of(**tags, [&](Tag tag) { return llvm::is_contained(possible, tag); }) ||
      (*tags)->size() == possible.size())
    return emitError() << "is refined to constructors not in normal form: ascending, once each, "
                       << "each one its indices leave possible, and fewer than all of them";
  if (!binders.empty() && determined(group, at, indices, (*tags)->front()))
    return emitError() << "keeps binders' terms its indices determine";
  return success();
}

// The parser's and bytecode's builder: what it reads is checked, then made
// in normal form, so a type has one spelling however it was written.
DataType DataType::getNormalized(function_ref<InFlightDiagnostic()> emitError, FamilyAttr group,
                                 uint32_t member, ArrayRef<TermNode> indices,
                                 DenseI32ArrayAttr refinement, ArrayRef<TermNode> binders) {
  FailureOr<std::optional<SmallVector<Tag>>> tags =
      checkParts(emitError, group, member, indices, refinement, binders);
  if (failed(tags))
    return {};
  DataType base = get(group.getContext(), group, member, indices);
  if (!*tags)
    return base;
  return (*tags)->size() == 1 ? base.refinedTo((*tags)->front(), binders) : base.refined(**tags);
}

//===----------------------------------------------------------------------===//
// What a reader asks of a data type
//===----------------------------------------------------------------------===//


const TagSet &DataType::possibleTags() const { return getImpl()->possible; }

std::optional<Tag> DataType::singleTag() const {
  if (possibleTags().size() != 1)
    return std::nullopt;
  return possibleTags().front();
}

uint32_t DataType::declaredCount() const { return getGroup().tagCount(getMember()); }
MemberKind DataType::kind() const { return getGroup().memberKind(getMember()); }
CtorView DataType::ctor(Tag tag) const { return getGroup().ctor(getMember(), tag); }
ArrayRef<Sort> DataType::binderSorts(Tag tag) const { return ctor(tag).binders; }
std::optional<MemoView> DataType::memo() const { return getGroup().memo(getMember()); }
std::optional<ClosuresView> DataType::closures() const {
  return getGroup().closures(getMember());
}
std::optional<ListShape> DataType::listShape() const { return getGroup().listShape(getMember()); }
Promise DataType::promise() const { return getGroup().promise(getMember()); }

FlatSymbolRefAttr DataType::labelFunction(Tag tag) const {
  return getGroup().labelFunction(getMember(), tag);
}

std::optional<Mode> DataType::labelMode(Tag tag) const {
  return getGroup().labelMode(getMember(), tag);
}

Layout DataType::layout() const { return getImpl()->facts.layout; }
Class DataType::cls() const { return getImpl()->facts.cls; }
uint32_t DataType::components() const { return getImpl()->facts.components; }
bool DataType::boundsReach() const { return getImpl()->facts.reach == Reach::Bounded; }
ArrayRef<FieldRef> DataType::inPlaceFields() const {
  return getGroup().inPlaceFields(getMember());
}
ArrayRef<MemberRef> DataType::selfCells() const { return getGroup().selfCells(getMember()); }
uint32_t DataType::freeLevels() const { return getImpl()->freeLevels; }

// The binders of `tag` this type gives: its own, when it is refined to
// that constructor with them; else those its indices determine.
std::optional<SmallVector<TermNode>> DataType::bindersOf(Tag tag) const {
  if (!getBinders().empty() && singleTag() == tag)
    return SmallVector<TermNode>(getBinders());
  return determined(getGroup(), getMember(), getIndices(), tag);
}

// The fields of `tag` at this application: each field type with the
// constructor's binders replaced by their terms here, a member of the
// group named by position becoming its data type. Made where a builder or
// a verifier asks, never on a worker's hot path: a pass reads a field's
// type off the IR that holds it.
std::optional<SmallVector<Type>> DataType::determinedFields(Tag tag) const {
  std::optional<SmallVector<TermNode>> binders = bindersOf(tag);
  if (!binders)
    return std::nullopt;
  return instantiateFields(getGroup(), ctor(tag).fields,
                           termsOf(*binders, ctor(tag).binders.size()));
}

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

//===----------------------------------------------------------------------===//
// How a data type is written
//===----------------------------------------------------------------------===//

// `!idr.data<#Vect[v0]>`, `!idr.data<#Tree at 1 [v0]>`, refined
// `!idr.data<#List @Cons>`, `!idr.data<#T {@A, @B}>`, `!idr.data<#Ex
// @MkEx<v3>>`: the group by its alias, the member after `at` when it is
// not the first, the indices when there are any, the refinement.
void DataType::print(AsmPrinter &printer) const {
  FamilyAttr group = getGroup();
  printer << '<';
  printer.printAttribute(group);
  if (getMember() != 0)
    printer << " at " << getMember();
  size_t count = group.indices(getMember()).size();
  if (count > 0) {
    printer << '[';
    printTerms(printer, getIndices(), count, group);
    printer << ']';
  }
  SmallVector<Tag> tags;
  if (getRefinement())
    tags.assign(possibleTags().begin(), possibleTags().end());
  if (getRefinement() && tags.empty()) {
    printer << " {}";
  } else if (tags.size() == 1) {
    printer << ' ';
    printer.printSymbolName(ctor(tags.front()).label);
    if (!getBinders().empty()) {
      printer << '<';
      printTerms(printer, getBinders(), ctor(tags.front()).binders.size(), group);
      printer << '>';
    }
  } else if (!tags.empty()) {
    printer << " {";
    llvm::interleaveComma(tags, printer,
                          [&](Tag tag) { printer.printSymbolName(ctor(tag).label); });
    printer << '}';
  }
  printer << '>';
}

Type DataType::parse(AsmParser &parser) {
  SMLoc loc = parser.getCurrentLocation();
  FamilyAttr group;
  uint32_t member = 0;
  if (parser.parseLess() || parser.parseAttribute(group))
    return {};
  if (succeeded(parser.parseOptionalKeyword("at")) && parser.parseInteger(member))
    return {};
  if (member >= group.getMembers().size()) {
    parser.emitError(loc, "expects a member of the family");
    return {};
  }
  SmallVector<TermNode> indices;
  size_t count = group.indices(member).size();
  if (count > 0 && (parser.parseLSquare() || parseTerms(parser, count, indices, nullptr) ||
                    parser.parseRSquare()))
    return {};
  auto labelTag = [&](Tag &tag) -> ParseResult {
    std::string label;
    SMLoc at = parser.getCurrentLocation();
    if (parser.parseSymbolName(label))
      return failure();
    std::optional<Tag> found = group.tagOf(member, label);
    if (!found)
      return parser.emitError(at, "expects a constructor of the family, got @") << label;
    tag = *found;
    return success();
  };
  // No refinement, a set of constructors (`{}` for none), or one
  // constructor with the terms of its undetermined binders.
  std::optional<SmallVector<Tag>> tags;
  SmallVector<TermNode> binders;
  if (succeeded(parser.parseOptionalLBrace())) {
    tags.emplace();
    if (failed(parser.parseOptionalRBrace()) &&
        (parser.parseCommaSeparatedList([&]() { return labelTag(tags->emplace_back()); }) ||
         parser.parseRBrace()))
      return {};
    llvm::sort(*tags);
  } else {
    StringAttr label;
    SMLoc at = parser.getCurrentLocation();
    if (succeeded(parser.parseOptionalSymbolName(label))) {
      std::optional<Tag> found = group.tagOf(member, label.getValue());
      if (!found) {
        parser.emitError(at, "expects a constructor of the family, got @") << label.getValue();
        return {};
      }
      tags.emplace(1, *found);
      if (succeeded(parser.parseOptionalLess()) &&
          (parseTerms(parser, group.ctor(member, *found).binders.size(), binders, nullptr) ||
           parser.parseGreater()))
        return {};
    }
  }
  if (parser.parseGreater())
    return {};
  DenseI32ArrayAttr refinement;
  if (tags)
    refinement = tagsAttr(parser.getContext(), *tags);
  return getNormalized([&] { return parser.emitError(loc); }, group, member, indices, refinement,
                       binders);
}
