// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One type against another with the levels of the second instantiated by
// one substitution, consistently through the whole type: what MLIR's
// verifier asks of a region's entry and of a jump, with no context. The
// exact substitution is the scope walk's, which knows the scope; this is
// the check upstream's region-branch verifier can make on its own.

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Unify.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;

namespace idr::families {

namespace {

// Where a type is met: at the top of a value's type, or inside another
// type, where no data type is narrowed, since only a case's scrutinee is
// refined.
enum class Depth : uint8_t { Top, Inner };

class Matcher {
public:
  explicit Matcher(Narrowing narrowing)
      : narrowing(narrowing), subst(0, 0, Freedom::Rigid, Freedom::Unknown, Opacity::StaysOpen, Attribute()) {}

  // Whether `instance` is `pattern` under the substitution being built: the
  // pattern's levels free, the instance's fixed, an opaque index of the
  // instance open. A data type at the top may narrow; one inside another
  // type may not.
  bool match(Type pattern, Type instance, Depth depth);

private:
  bool terms(ArrayRef<TermNode> pattern, ArrayRef<TermNode> instance, size_t count);

  Narrowing narrowing;
  Subst subst;
};

bool Matcher::terms(ArrayRef<TermNode> pattern, ArrayRef<TermNode> instance, size_t count) {
  return unifyAll(subst, instance, pattern, count) == Unified::Consistent;
}

bool Matcher::match(Type pattern, Type instance, Depth depth) {
  if (pattern == instance)
    return true;
  if (pattern.getTypeID() != instance.getTypeID())
    return false;
  if (auto p = dyn_cast<DataType>(pattern)) {
    auto i = cast<DataType>(instance);
    if (p.getGroup() != i.getGroup() || p.getMember() != i.getMember() ||
        !terms(p.getIndices(), i.getIndices(), p.getGroup().indices(p.getMember()).size()))
      return false;
    if (depth == Depth::Top && narrowing == Narrowing::Allowed)
      return p.possibleTags().includes(i.possibleTags());
    return p.getRefinement() == i.getRefinement();
  }
  if (auto p = dyn_cast<NatType>(pattern))
    return terms(p.getIndex(), cast<NatType>(instance).getIndex(), 1);
  if (auto p = dyn_cast<GradedType>(pattern)) {
    auto i = cast<GradedType>(instance);
    return p.getUses() == i.getUses() && p.getHold() == i.getHold() &&
           match(p.getCarrier(), i.getCarrier(), depth);
  }
  if (auto p = dyn_cast<ShapedType>(pattern))
    if (p.getShape() != cast<ShapedType>(instance).getShape())
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
  for (auto [p, i] : llvm::zip_equal(pt, it))
    if (!match(p, i, Depth::Inner))
      return false;
  return true;
}

} // namespace

bool TagSet::contains(Tag tag) const {
  if (all > 0)
    return static_cast<uint32_t>(tag) < all;
  return llvm::is_contained(listed_, tag);
}

bool TagSet::includes(const TagSet &other) const {
  return llvm::all_of(other, [&](Tag tag) { return contains(tag); });
}

bool refines(Type sub, Type super) {
  return Matcher(Narrowing::Allowed).match(super, sub, Depth::Top);
}

bool instanceOf(Type instance, Type pattern) {
  return Matcher(Narrowing::Exact).match(pattern, instance, Depth::Top);
}

} // namespace idr::families
