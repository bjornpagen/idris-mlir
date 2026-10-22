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
  bool match(Type pattern, Type instance);

private:
  // A pattern and its instance still to match, and where they are met.
  struct Pair {
    Type pattern;
    Type instance;
    Depth depth;
  };

  // Whether the pair's own parts match, each pair of types inside them
  // pushed on `pending`, so a type nests as deep as the program writes it
  // and the matcher's depth is none of it.
  bool step(const Pair &pair, SmallVectorImpl<Pair> &pending);
  bool terms(ArrayRef<TermNode> pattern, ArrayRef<TermNode> instance, size_t count);

  Narrowing narrowing;
  Subst subst;
};

bool Matcher::terms(ArrayRef<TermNode> pattern, ArrayRef<TermNode> instance, size_t count) {
  return unifyAll(subst, instance, pattern, count) == Unified::Consistent;
}

bool Matcher::match(Type pattern, Type instance) {
  SmallVector<Pair> pending{{pattern, instance, Depth::Top}};
  while (!pending.empty())
    if (!step(pending.pop_back_val(), pending))
      return false;
  return true;
}

bool Matcher::step(const Pair &pair, SmallVectorImpl<Pair> &pending) {
  auto [pattern, instance, depth] = pair;
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
    if (p.getUses() != i.getUses() || p.getHold() != i.getHold())
      return false;
    pending.push_back({p.getCarrier(), i.getCarrier(), depth});
    return true;
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
  // Pushed last first, so the parts are met left to right.
  for (auto [p, i] : llvm::reverse(llvm::zip_equal(pt, it)))
    pending.push_back({p, i, Depth::Inner});
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
  return Matcher(Narrowing::Allowed).match(super, sub);
}

bool instanceOf(Type instance, Type pattern) {
  return Matcher(Narrowing::Exact).match(pattern, instance);
}

} // namespace idr::families
