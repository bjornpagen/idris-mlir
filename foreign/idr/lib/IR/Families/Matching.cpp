// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One type against another with the levels of the second instantiated by
// one substitution, consistently through the whole type: what MLIR's
// verifier asks of a region's entry and of a jump, with no context. The
// exact substitution is the scope walk's, which knows the scope; this is
// the check upstream's region-branch verifier can make on its own. A type
// whose match reads more than its parts answers PatternTypeInterface; any
// other matches part by part.

#include "idr/IR/Families/Matching.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::families {

PatternMatch::PatternMatch(Narrowing narrowing)
    : narrowing(narrowing), subst(0, 0, Freedom::Rigid, Freedom::Unknown, Opacity::StaysOpen, Attribute()) {}

// A refinement (a cast, a case's binding) takes the program's word for an
// index Idris proved and the language cannot write: the term holding it is
// the pattern's term there, so a cast from `Vect (length xs)` is admitted
// to `Vect n` and, in a copy that closes `n`, to `Vect 3` alike, its
// constructors those the term it is taken for leaves possible, and whether
// a function verifies never changes under a substitution of its levels.
// The pattern's levels are moved past the instance's, so a pattern level
// the taken term names is a level of the instance no other term names, and
// the substitution binds it there. An instance of a pattern (a jump's
// argument, a call's operand) names only the indices the pattern does, so
// its terms are read as written, and an opaque one meets only an opaque
// term or a free level.
std::optional<SmallVector<TermNode>> PatternMatch::readInstance(ArrayRef<TermNode> pattern,
                                                               ArrayRef<TermNode> instance,
                                                               size_t count,
                                                               uint32_t levels) const {
  auto opaque = [](const TermNode &node) { return node.kind == TermKind::Opaque; };
  if (narrowing == Narrowing::Exact || llvm::none_of(instance, opaque))
    return std::nullopt;
  SmallVector<TermNode> read;
  TermWriter write(read);
  for (auto [own, given] : llvm::zip_equal(termsOf(pattern, count), termsOf(instance, count)))
    if (llvm::any_of(given.nodes(), opaque))
      write.copy(own, 0, levels);
    else
      write.copy(given);
  return read;
}

bool PatternMatch::terms(ArrayRef<TermNode> pattern, ArrayRef<TermNode> instance, size_t count) {
  return unifyAll(subst, instance, pattern, count) == Unified::Consistent;
}

bool PatternMatch::mayNarrow() const { return at == Depth::Top && narrowing == Narrowing::Allowed; }

void PatternMatch::queue(Type pattern, Type instance) { pending.push_back({pattern, instance, at}); }

bool PatternMatch::match(Type pattern, Type instance) {
  pending.assign({{pattern, instance, Depth::Top}});
  while (!pending.empty())
    if (!step(pending.pop_back_val()))
      return false;
  return true;
}

bool PatternMatch::step(const Pair &pair) {
  auto [pattern, instance, depth] = pair;
  if (pattern == instance)
    return true;
  if (pattern.getTypeID() != instance.getTypeID())
    return false;
  at = depth;
  if (auto own = dyn_cast<PatternTypeInterface>(pattern))
    return own.matchInstance(instance, *this);
  // An upstream shaped type's extents are no part MLIR's walk gives, so
  // they are compared before its parts.
  if (auto shaped = dyn_cast<ShapedType>(pattern))
    if (shaped.getShape() != cast<ShapedType>(instance).getShape())
      return false;
  // Any other type matches where its parts do, part by part: the same
  // kind of type, whose types match and whose attributes are equal.
  SmallVector<Type> pt, it;
  SmallVector<Attribute> pa, ia;
  pattern.walkImmediateSubElements([&](Attribute a) { pa.push_back(a); },
                                   [&](Type t) { pt.push_back(t); });
  instance.walkImmediateSubElements([&](Attribute a) { ia.push_back(a); },
                                    [&](Type t) { it.push_back(t); });
  if (pt.size() != it.size() || pa != ia)
    return false;
  // Pushed last first, so the parts are met left to right.
  for (auto [p, i] : llvm::reverse(llvm::zip_equal(pt, it)))
    pending.push_back({p, i, Depth::Inner});
  return true;
}

bool TagSet::contains(Tag tag) const {
  if (all > 0)
    return static_cast<uint32_t>(tag) < all;
  return llvm::is_contained(listed_, tag);
}

bool TagSet::includes(const TagSet &other) const {
  return llvm::all_of(other, [&](Tag tag) { return contains(tag); });
}

bool refines(Type sub, Type super) { return PatternMatch(Narrowing::Allowed).match(super, sub); }

bool instanceOf(Type instance, Type pattern) {
  return PatternMatch(Narrowing::Exact).match(pattern, instance);
}

} // namespace idr::families

namespace idr {

// A data type matches one of its family and member whose index terms its
// own instantiate, as the match reads them; at the top, where narrowing is
// allowed, its possible constructors include the instance's, and elsewhere
// the refinements are one. Where the match took a term of the instance on
// the program's word, the instance holds only the constructors the terms
// it read leave possible, among its own. The caller met two types of one
// class.
bool DataType::matchInstance(Type instance, families::PatternMatch &match) const {
  auto other = cast<DataType>(instance);
  if (getGroup() != other.getGroup() || getMember() != other.getMember())
    return false;
  size_t count = getGroup().indices(getMember()).size();
  std::optional<SmallVector<families::TermNode>> taken =
      match.readInstance(getIndices(), other.getIndices(), count, other.freeLevels());
  if (!match.terms(getIndices(), taken ? ArrayRef<families::TermNode>(*taken) : other.getIndices(),
                   count))
    return false;
  if (!match.mayNarrow())
    return getRefinement() == other.getRefinement();
  if (!taken)
    return possibleTags().includes(other.possibleTags());
  return llvm::all_of(families::possibleAt(getGroup(), getMember(), *taken), [&](Tag tag) {
    return !other.possibleTags().contains(tag) || possibleTags().contains(tag);
  });
}

// A natural matches where its one index term does, as the match reads it.
bool NatType::matchInstance(Type instance, families::PatternMatch &match) const {
  ArrayRef<families::TermNode> given = cast<NatType>(instance).getIndex();
  std::optional<SmallVector<families::TermNode>> taken =
      match.readInstance(getIndex(), given, 1, families::freeLevelsOf(given));
  return match.terms(getIndex(), taken ? ArrayRef<families::TermNode>(*taken) : given, 1);
}

// A grade matches one of the same uses and hold, its carrier matched where
// the grade is met.
bool GradedType::matchInstance(Type instance, families::PatternMatch &match) const {
  auto other = cast<GradedType>(instance);
  if (getUses() != other.getUses() || getHold() != other.getHold())
    return false;
  match.queue(getCarrier(), other.getCarrier());
  return true;
}

} // namespace idr
