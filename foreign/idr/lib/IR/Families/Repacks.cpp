// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether re-packing a value from one layout into another builds a cell or
// an array: one answer, which the reindex's verifier, its flow, a field
// read's type and flow, and the lowering's re-pack read. It is decided
// from what the two types stored when they were made and from their index
// terms, as the class rule decides a class (lib/IR/Layout/Classes.cpp), and
// it makes no type or attribute, so a lowering worker asks it as a verifier
// does. Beside it, the hold what such a re-pack builds is given, which the
// reindex's verifier and every builder of a reindex read (builtHold).
//
// Two applications of one member are compared by their placements
// (layoutMatch). The same words build nothing, and neither does a number
// widened or narrowed; a value re-packed into a cell builds one; into a
// value held in place, it builds where re-packing a field of a constructor
// both leave possible does. A field is its constructor's declared type at
// the terms its holder's substitution writes: the binders the holder's
// closed indices solve where the holder is its own unfolding, as the class
// rule laid it out, field by field, and the constructor's own binders
// elsewhere. Where those terms are closed, the field's class is read off
// the holder's unfolding, which unfolded it; elsewhere it is the rule's.
// An array field builds where its elements lay out apart, which copies it
// into a fresh array.
//
// Values in place nest as deep as the program writes them, so the pairs
// wait on a stack that grows on the heap.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <algorithm>
#include <cassert>
#include <optional>
#include <utility>
#include <variant>

using namespace mlir;

namespace idr::families {

namespace {

// An application whose type was made: its facts are the ones it stored.
struct Made {
  DataType type;
};

// An application the walk wrote for a field: its class is the rule's at
// the written terms, read off the holder's unfolding or run, and its
// constructors are those the terms leave possible among those its declared
// type keeps.
struct Written {
  Unfolding unfolding;
  TagSet kept;
};

// One of the two applications a pair compares: a member applied to terms
// it owns, laid out as its mark says, and where its facts come from.
struct Applied {
  FamilyAttr group;
  uint32_t member;
  SmallVector<TermNode> indices;
  LayoutMark mark;
  std::variant<Made, Written> origin;
};

Applied madeApplied(DataType type) {
  return Applied{type.getGroup(), type.getMember(), SmallVector<TermNode>(type.getIndices()),
                 type.getMark(), Made{type}};
}

// Where `applied` is laid out: as its type stored, or as the class rule
// lays its written terms out. The placement views its terms.
Placed placementOf(const Applied &applied) {
  auto [cls, layout] = match(
      applied.origin,
      [](const Made &made) { return std::pair(made.type.cls(), made.type.layout()); },
      [&](const Written &written) {
        return classAt(applied.group, applied.member, applied.indices, applied.mark,
                       written.unfolding);
      });
  return Placed{applied.group, applied.member, applied.indices, applied.mark, cls, layout};
}

// The constructors a value of `applied` may hold: as its type stored them,
// or those its written terms leave possible among those its declared type
// keeps.
SmallVector<Tag> possibleOf(const Applied &applied) {
  return match(
      applied.origin,
      [](const Made &made) {
        const TagSet &possible = made.type.possibleTags();
        return SmallVector<Tag>(possible.begin(), possible.end());
      },
      [&](const Written &written) {
        SmallVector<Tag> possible = possibleAt(applied.group, applied.member, applied.indices);
        llvm::erase_if(possible, [&](Tag tag) { return !written.kept.contains(tag); });
        return possible;
      });
}

// How a holder lays its constructors' fields out: at the binders its closed
// indices solve, being its own unfolding; or at the constructor's own
// binders, a cell's fields and those of a value in place at an unknown
// class alike.
enum class FieldsAt : uint8_t { Solved, Own };

FieldsAt fieldsAtOf(const Placed &holder) {
  return holder.layout == Layout::InPlace && holder.cls == Class::Closed ? FieldsAt::Solved
                                                                         : FieldsAt::Own;
}

// How a written field's class is known: off its holder's unfolding where
// that holder is one, else by the rule.
Unfolding unfoldingOf(FieldsAt at) {
  switch (at) {
  case FieldsAt::Solved:
    return Unfolding::ByHolder;
  case FieldsAt::Own:
    return Unfolding::Run;
  }
  llvm_unreachable("a holder lays its fields out at solved binders or at its own");
}

// The substitution `holder` lays constructor `tag`'s fields out under, as
// the class rule unfolded it: its terms and the constructor's equation,
// the binders unknowns, where they are solved; none bound where they are
// its own. The substitution views `holder`'s terms, which outlive it.
Subst layoutSubst(const Applied &holder, Tag tag, FieldsAt at) {
  CtorView ctor = holder.group.ctor(holder.member, tag);
  Subst subst(0, static_cast<uint32_t>(ctor.binders.size()), Freedom::Rigid, Freedom::Unknown,
              Opacity::MeetsAnything, holder.group);
  switch (at) {
  case FieldsAt::Solved:
    // A constructor the walk reaches is one both sides leave possible, so
    // its equation meets the holder's terms.
    (void)unifyAll(subst, holder.indices, ctor.equation,
                   holder.group.indices(holder.member).size());
    return subst;
  case FieldsAt::Own:
    return subst;
  }
  llvm_unreachable("a holder lays its fields out at solved binders or at its own");
}

// `named` at the terms `subst` writes for its own.
Applied writtenApplied(const NamedApplication &named, const Subst &subst, Unfolding unfolding) {
  Applied applied{named.group, named.member, {}, named.mark, Written{unfolding, named.kept()}};
  TermWriter write(applied.indices);
  for (Term term : termsOf(named.terms, named.group.indices(named.member).size()))
    (void)subst.write(write, term, Side::Constructor, 0);
  return applied;
}

// What a pair re-packs: a value, or an array's elements, which re-pack
// only by copying the array into a fresh one.
enum class Repacked : uint8_t { Value, Elements };

struct Pair {
  Applied source;
  Applied target;
  Repacked repacked;
};

// The pair one declared field makes, `source` its terms under one
// substitution and `target` under the other: the application the field
// names, or the one its array's elements name, whose class no holder's
// unfolding read; none where it names none, or both sides are one
// application, the same words.
std::optional<Pair> fieldPair(FamilyAttr holder, Type declared, const Subst &source,
                              Unfolding sourceBy, const Subst &target, Unfolding targetBy) {
  Type field = unrestricted(declared);
  Repacked repacked = Repacked::Value;
  if (auto array = dyn_cast<MemRefType>(field)) {
    field = array.getElementType();
    repacked = Repacked::Elements;
    sourceBy = Unfolding::Run;
    targetBy = Unfolding::Run;
  }
  std::optional<NamedApplication> named = namedBy(holder, field);
  if (!named)
    return std::nullopt;
  Applied from = writtenApplied(*named, source, sourceBy);
  Applied to = writtenApplied(*named, target, targetBy);
  if (from.indices == to.indices)
    return std::nullopt;
  return Pair{std::move(from), std::move(to), repacked};
}

// Whether re-packing `first` builds, each pair decided by its placements
// and, where it goes into a value held in place, by the fields of each
// constructor both leave possible.
bool repackBuilds(Pair first) {
  footprint::Vector<Pair> pending;
  pending.push_back(std::move(first));
  while (!pending.empty()) {
    Pair pair = std::move(pending.back());
    pending.pop_back();
    const Applied &source = pair.source;
    const Applied &target = pair.target;
    assert(source.group == target.group && source.member == target.member &&
           "a re-pack relates two applications of one member");
    Placed from = placementOf(source);
    Placed to = placementOf(target);
    if (layoutMatch(from, to) == LayoutMatch::SameLayout)
      continue;
    switch (pair.repacked) {
    case Repacked::Elements:
      return true;
    case Repacked::Value:
      break;
    }
    if (isNumber(from.layout))
      continue;
    if (to.layout != Layout::InPlace)
      return true;
    FieldsAt sourceAt = fieldsAtOf(from);
    FieldsAt targetAt = fieldsAtOf(to);
    SmallVector<Tag> held = possibleOf(target);
    for (Tag tag : possibleOf(source)) {
      if (!llvm::is_contained(held, tag))
        continue;
      Subst sourceSubst = layoutSubst(source, tag, sourceAt);
      Subst targetSubst = layoutSubst(target, tag, targetAt);
      for (Type declared : source.group.ctor(source.member, tag).fields)
        if (std::optional<Pair> next =
                fieldPair(source.group, declared, sourceSubst, unfoldingOf(sourceAt), targetSubst,
                          unfoldingOf(targetAt)))
          pending.push_back(std::move(*next));
    }
  }
  return false;
}

} // namespace

// Two data types are walked; a buffer whose elements lay out apart is
// copied into a fresh one, by its two element types' stored facts; a
// tensor's re-pack builds only once it is a buffer; any other value holds
// no layout an index decides.
bool builds(Type from, Type to) {
  Type source = unrestricted(from);
  Type target = unrestricted(to);
  auto sourceData = dyn_cast<DataType>(source);
  auto targetData = dyn_cast<DataType>(target);
  if (sourceData && targetData)
    return repackBuilds(Pair{madeApplied(sourceData), madeApplied(targetData), Repacked::Value});
  return isa<MemRefType>(target) && layoutMatch(source, target) == LayoutMatch::OtherLayout;
}

// A stated claim beyond the value's own cells stands: a builder that gives
// its operand up keeps, of the cells the operand reached, what the operand
// claimed of them.
Hold builtHold(Unique stated) { return Hold::counted(std::max(stated, Unique::Self)); }

// The slot is the field as the container's layout lays it out, under the
// substitution its unfolding solved where it is one; the read is the field
// at the binders the container's type gives that constructor, which its
// refinement keeps or its indices determine, and which no unfolding read.
bool fieldReadBuilds(Type container, unsigned index) {
  auto data = dyn_cast<DataType>(unrestricted(container));
  if (!data || !data.singleTag())
    return false;
  Tag tag = *data.singleTag();
  CtorView ctor = data.ctor(tag);
  std::optional<SmallVector<TermNode>> binders = data.bindersOf(tag);
  if (!binders || index >= ctor.fields.size())
    return false;
  Applied holder = madeApplied(data);
  FieldsAt at = fieldsAtOf(placementOf(holder));
  Subst slot = layoutSubst(holder, tag, at);
  auto count = static_cast<uint32_t>(ctor.binders.size());
  Subst read(freeLevelsOf(*binders), count, Freedom::Rigid, Freedom::Unknown,
             Opacity::MeetsAnything, data.getGroup());
  for (auto [binder, term] : llvm::enumerate(termsOf(*binders, count)))
    read.bind(Side::Constructor, binder, Bound{term.nodes(), Side::Application, 0});
  std::optional<Pair> pair = fieldPair(data.getGroup(), ctor.fields[index], slot,
                                       unfoldingOf(at), read, Unfolding::Run);
  return pair && repackBuilds(std::move(*pair));
}

} // namespace idr::families
