// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A data type's one spelling: its builders normalize a refinement (the
// constructors the indices exclude are dropped, a refinement to every
// constructor the indices allow is none unless it keeps a constructor's
// binders' terms, binders the indices determine are not kept), its verifier
// refuses any other, and the parser's and the
// bytecode's builder makes what it read in that form. A builder refines an
// application it holds, so what it makes is checked against what that
// application's storage keeps; only parts that arrive whole are checked by
// unifying again. Refining keeps the
// layout mark: the indices decide what is possible, and the mark how the
// value is laid out, which a case's refined value shares with what it
// refines. Then the binders and
// the fields of a constructor at the type's application, and whether a
// value is refined to one constructor whose binders it determines, which
// the constraints of a field read and a constructor value ask. Each type
// is made through the generated builder, whose storage is complete where
// the types are defined.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/FamilyStorage.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <algorithm>
#include <cassert>
#include <functional>
#include <optional>

using namespace mlir;
using namespace idr;
using namespace idr::families;

namespace {

// The terms of constructor `tag`'s binders its application's indices
// solve, one-way, the binders the unknowns and the application's levels
// rigid, written into `out`, each one they leave unbound as itself; and
// whether they left one unbound. None where the indices clash with the
// constructor's equation.
std::optional<Instance> solveBinders(FamilyAttr group, uint32_t member,
                                     ArrayRef<TermNode> indices, Tag tag,
                                     SmallVector<TermNode> &out) {
  CtorView ctor = group.ctor(member, tag);
  size_t count = group.indices(member).size();
  Subst subst(freeLevelsOf(indices), static_cast<uint32_t>(ctor.binders.size()), Freedom::Rigid,
              Freedom::Unknown, Opacity::MeetsAnything, group);
  if (unifyAll(subst, indices, ctor.equation, count) == Unified::Clash)
    return std::nullopt;
  TermWriter write(out);
  TermNode level{TermKind::Level, 0, 0, 0, Attribute()};
  Instance instance = Instance::Determined;
  for (uint32_t binder = 0; binder < ctor.binders.size(); ++binder) {
    level.value = binder;
    if (subst.write(write, Term(ArrayRef<TermNode>(level)), Side::Constructor, 0) ==
        Instance::Undetermined)
      instance = Instance::Undetermined;
  }
  return instance;
}

// The terms of constructor `tag`'s binders its application's indices
// determine. None where one stays unbound.
std::optional<SmallVector<TermNode>> determined(FamilyAttr group, uint32_t member,
                                                ArrayRef<TermNode> indices, Tag tag) {
  SmallVector<TermNode> out;
  if (solveBinders(group, member, indices, tag, out) != Instance::Determined)
    return std::nullopt;
  return out;
}

// Tags as the refinement holds them.
DenseI32ArrayAttr tagsAttr(MLIRContext *context, ArrayRef<Tag> tags) {
  SmallVector<int32_t> numbers = llvm::to_vector(
      llvm::map_range(tags, [](Tag tag) { return static_cast<int32_t>(tag); }));
  return DenseI32ArrayAttr::get(context, numbers);
}

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
  return idr::detail::refinementOf(base, tagsAttr(getContext(), kept), ArrayRef<TermNode>());
}

// The type refined to constructor `tag` alone, keeping `binders`, its
// binders' terms, where `tag` is possible and the indices leave them
// undetermined: the one decision of a refinement that unifies, which its
// verifier leaves to it.
DataType DataType::refinedTo(Tag tag, ArrayRef<TermNode> binders) const {
  if (binders.empty() || !possibleTags().contains(tag) ||
      determined(getGroup(), getMember(), getIndices(), tag))
    return refined({tag});
  return idr::detail::refinementOf(unrefined(), tagsAttr(getContext(), {tag}), binders);
}

namespace {

// What every builder from parts no builder of ours made checks first: a
// member of the family, one whole term per index, refined tags the member
// declares, and binders' terms, whole, one per binder of the one
// constructor a refinement names. The tags as read, ascending and once
// each; none where the type is unrefined.
FailureOr<std::optional<SmallVector<Tag>>>
checkParts(function_ref<InFlightDiagnostic()> emitError, FamilyAttr group, uint32_t at,
           ArrayRef<TermNode> indices, DenseI32ArrayAttr refinement, ArrayRef<TermNode> binders) {
  if (!group || at >= group.getMembers().size())
    return emitError() << "expects a member of the family";
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

// A type built from its parts (an application, or a type whose parts a
// replacement gives whole), its one spelling: what it was checked for, and
// its refinement in normal form, ascending, to constructors its indices
// leave possible and fewer than all of them, its binders kept only where
// the indices leave them undetermined. A refinement to one constructor
// that keeps its binders' terms says what the unrefined type cannot, so it
// stands where that constructor is the only one possible (refinedTo makes
// it so).
LogicalResult DataType::verify(function_ref<InFlightDiagnostic()> emitError, FamilyAttr group,
                               uint32_t at, ArrayRef<TermNode> indices,
                               DenseI32ArrayAttr refinement, ArrayRef<TermNode> binders,
                               LayoutMark) {
  FailureOr<std::optional<SmallVector<Tag>>> tags =
      checkParts(emitError, group, at, indices, refinement, binders);
  if (failed(tags))
    return failure();
  if (!*tags)
    return success();
  SmallVector<Tag> possible = possibleAt(group, at, indices);
  if ((*tags)->size() != refinement.asArrayRef().size() ||
      !llvm::all_of(**tags, [&](Tag tag) { return llvm::is_contained(possible, tag); }) ||
      ((*tags)->size() == possible.size() && binders.empty()))
    return emitError() << "is refined to constructors not in normal form: ascending, once each, "
                       << "each one its indices leave possible, and fewer than all of them "
                       << "unless it keeps one constructor's binders' terms";
  if (!binders.empty() && determined(group, at, indices, (*tags)->front()))
    return emitError() << "keeps binders' terms its indices determine";
  return success();
}

// A refinement a builder makes of `base`, an unrefined application it
// holds: the same normal form, checked against the constructors the
// application's storage keeps as possible, with no unification. Whether
// the binders' terms are ones the indices leave undetermined is refinedTo's
// decision, made once where they are given.
LogicalResult DataType::verifyInvariants(function_ref<InFlightDiagnostic()> emitError,
                                         DataType base, DenseI32ArrayAttr refinement,
                                         ArrayRef<TermNode> binders) {
  if (!base || base.unrefined() != base || !refinement)
    return emitError() << "refines what is no unrefined application, or names no refinement";
  ArrayRef<int32_t> tags = refinement.asArrayRef();
  const TagSet &possible = base.possibleTags();
  auto isPossible = [&](int32_t tag) {
    return tag >= 0 && possible.contains(Tag{static_cast<uint32_t>(tag)});
  };
  if (!llvm::all_of(tags, isPossible) ||
      std::adjacent_find(tags.begin(), tags.end(), std::greater_equal<int32_t>()) != tags.end() ||
      (tags.size() == possible.size() && binders.empty()))
    return emitError() << "is refined to constructors not in normal form: ascending, once each, "
                       << "each one its indices leave possible, and fewer than all of them "
                       << "unless it keeps one constructor's binders' terms";
  if (!binders.empty() &&
      (tags.size() != 1 ||
       countTerms(binders) != base.ctor(Tag{static_cast<uint32_t>(tags.front())}).binders.size()))
    return emitError() << "gives binders' terms to no one constructor, or not one per binder";
  return success();
}

// The parser's and bytecode's builder: what it reads is checked, then made
// in normal form, so a type has one spelling however it was written. It
// takes its diagnostic callback in the form upstream's getChecked and
// verify do, since it runs the check `verify` runs. Any mark is in normal
// form: it is a layout's, which no index excludes.
DataType DataType::getNormalized(function_ref<InFlightDiagnostic()> emitError, FamilyAttr group,
                                 uint32_t member, ArrayRef<TermNode> indices,
                                 DenseI32ArrayAttr refinement, ArrayRef<TermNode> binders,
                                 LayoutMark mark) {
  FailureOr<std::optional<SmallVector<Tag>>> tags =
      checkParts(emitError, group, member, indices, refinement, binders);
  if (failed(tags))
    return {};
  DataType base = get(group.getContext(), group, member, indices).marked(mark);
  if (!*tags)
    return base;
  return (*tags)->size() == 1 ? base.refinedTo((*tags)->front(), binders) : base.refined(**tags);
}

// The binders of `tag` this type gives: its own, when it is refined to
// that constructor with them; else those its indices determine.
std::optional<SmallVector<TermNode>> DataType::bindersOf(Tag tag) const {
  if (!getBinders().empty() && singleTag() == tag)
    return SmallVector<TermNode>(getBinders());
  return determined(getGroup(), getMember(), getIndices(), tag);
}

// A closed application names no level of its own, so a binder its indices
// leave open, written as itself, is the constructor's own binder in the
// field it is written into, as the class rule's unfolding writes it.
SmallVector<TermNode> idr::families::solvedBinders(FamilyAttr group, uint32_t member,
                                                   ArrayRef<TermNode> indices, Tag tag) {
  assert(llvm::all_of(termsOf(indices, group.indices(member).size()),
                      [](Term term) { return term.isClosed(); }) &&
         "a binder left open is the constructor's own only where the application names no "
         "level");
  SmallVector<TermNode> out;
  if (!solveBinders(group, member, indices, tag, out))
    llvm::reportFatalInternalError(
        "the binders of a constructor its application's indices leave impossible");
  return out;
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

// A value refined to one constructor whose binders its type determines, at
// any grade: what a field is a total read of, and what a constructor
// value builds. Its fields are determined exactly where its binders are,
// which this asks, so the constraint makes no field type.
bool idr::isRefinedValue(Type type) {
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data)
    return false;
  std::optional<Tag> tag = data.singleTag();
  return tag && data.bindersOf(*tag);
}
