// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A data type's one spelling: its builders normalize a refinement (the
// constructors the indices exclude are dropped, a refinement to every
// constructor the indices allow is none, binders the indices determine are
// not kept), its verifier refuses any other, and the parser's and the
// bytecode's builder makes what it read in that form. Then the binders and
// the fields of a constructor at the type's application. Each type is made
// through the generated builder, whose storage is complete where the types
// are defined.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;
using namespace idr::families;

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

// Tags as the refinement holds them.
DenseI32ArrayAttr tagsAttr(MLIRContext *context, ArrayRef<Tag> tags) {
  SmallVector<int32_t> numbers = llvm::to_vector(
      llvm::map_range(tags, [](Tag tag) { return static_cast<int32_t>(tag); }));
  return DenseI32ArrayAttr::get(context, numbers);
}

uint32_t memberOf(DataType type) { return static_cast<uint32_t>(type.getMember()); }

} // namespace

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
  return get(getContext(), getGroup(), getMember(), getIndices(), tagsAttr(getContext(), kept),
             ArrayRef<TermNode>());
}

DataType DataType::refinedTo(Tag tag, ArrayRef<TermNode> binders) const {
  DataType one = refined({tag});
  if (binders.empty() || !one.singleTag() ||
      determined(getGroup(), memberOf(*this), getIndices(), tag))
    return one;
  return get(getContext(), getGroup(), getMember(), getIndices(), tagsAttr(getContext(), {tag}),
             binders);
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

// The binders of `tag` this type gives: its own, when it is refined to
// that constructor with them; else those its indices determine.
std::optional<SmallVector<TermNode>> DataType::bindersOf(Tag tag) const {
  if (!getBinders().empty() && singleTag() == tag)
    return SmallVector<TermNode>(getBinders());
  return determined(getGroup(), memberOf(*this), getIndices(), tag);
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
