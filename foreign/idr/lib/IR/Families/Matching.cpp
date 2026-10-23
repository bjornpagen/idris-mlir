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

using namespace mlir;

namespace idr::families {

PatternMatch::PatternMatch(Narrowing narrowing)
    : narrowing(narrowing), subst(0, 0, Freedom::Rigid, Freedom::Unknown, Opacity::StaysOpen, Attribute()) {}

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
// own instantiate; at the top, where narrowing is allowed, its possible
// constructors include the instance's, and elsewhere the refinements are
// one. The caller met two types of one class.
bool DataType::matchInstance(Type instance, families::PatternMatch &match) const {
  auto other = cast<DataType>(instance);
  if (getGroup() != other.getGroup() || getMember() != other.getMember() ||
      !match.terms(getIndices(), other.getIndices(), getGroup().indices(getMember()).size()))
    return false;
  if (match.mayNarrow())
    return possibleTags().includes(other.possibleTags());
  return getRefinement() == other.getRefinement();
}

// A natural matches where its one index term does.
bool NatType::matchInstance(Type instance, families::PatternMatch &match) const {
  return match.terms(getIndex(), cast<NatType>(instance).getIndex(), 1);
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
