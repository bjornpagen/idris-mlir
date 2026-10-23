// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// First-order unification of index terms, Idris's `conflict` restated over
// the index language: distinct constructors clash, and so do distinct
// literals and naturals, and a level that occurs in its own binding under a
// constructor or a successor; an opaque term clashes with nothing and binds
// nothing, and so does a rigid level, but where the application side's
// opaque terms stay open. A sum of naturals is what base's `plus` gives,
// which Idris's `conflict` sees as a stuck application: it clashes with
// nothing and its parts learn nothing, and only a free level is bound to
// it. Everything is plain arrays and words:
// a successor peeled off a term is a count beside its view, and a natural
// that meets a successor leaves a smaller natural with no node of its own.
// No step recurses on a term's depth: a term's arguments wait on a stack.

#include "idr/IR/Families/Unify.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <limits>
#include <utility>

namespace idr::families {

namespace {

// The term every overflowing count is: past a word, a natural refines
// nothing.
const TermNode opaqueNode{TermKind::Opaque, 0, 0, 0, mlir::Attribute()};

Bound opaqueBound(Side side) { return Bound{llvm::ArrayRef<TermNode>(opaqueNode), side, 0}; }

bool isConstant(const Bound &b) { return b.nodes.empty(); }

const TermNode &headOf(const Bound &b) { return b.nodes.front(); }

std::optional<uint64_t> add(uint64_t a, uint64_t b) {
  if (a > std::numeric_limits<uint64_t>::max() - b)
    return std::nullopt;
  return a + b;
}

std::optional<uint64_t> multiply(uint64_t a, uint64_t b) {
  if (b != 0 && a > std::numeric_limits<uint64_t>::max() / b)
    return std::nullopt;
  return a * b;
}

} // namespace

Subst::Subst(uint32_t applicationLevels, uint32_t constructorLevels, Freedom applicationFree,
             Freedom constructorFree, Opacity opacity, mlir::Attribute own)
    : application(applicationLevels), constructor(constructorLevels),
      applicationFreedom(applicationFree), constructorFreedom(constructorFree), opaque(opacity),
      own(own) {}

std::optional<Bound> Subst::lookup(Side side, uint64_t level) const {
  const auto &levels = side == Side::Application ? application : constructor;
  return level < levels.size() ? levels[level] : std::nullopt;
}

bool Subst::isFree(Side side) const {
  return (side == Side::Application ? applicationFreedom : constructorFreedom) == Freedom::Unknown;
}

void Subst::bind(Side side, uint64_t level, Bound to) {
  auto &levels = side == Side::Application ? application : constructor;
  if (level >= levels.size())
    levels.resize(level + 1);
  levels[level] = to;
}

namespace {

// `b` with its successors peeled into its count and its bound levels
// replaced by their bindings: its head is then a natural (no nodes), a
// level no binding has, a sum, a literal, a constructor, or opaque. A sum's
// own levels are resolved where it is written, not here.
Bound normal(const Subst &subst, Bound b) {
  while (!isConstant(b)) {
    const TermNode &head = headOf(b);
    switch (head.kind) {
    case TermKind::Successor: {
      std::optional<uint64_t> plus = add(b.plus, head.value);
      if (!plus)
        return opaqueBound(b.side);
      b = Bound{b.nodes.drop_front(), b.side, *plus};
      continue;
    }
    case TermKind::Natural: {
      std::optional<uint64_t> value = add(b.plus, head.value);
      if (!value)
        return opaqueBound(b.side);
      return Bound{{}, b.side, *value};
    }
    case TermKind::Level: {
      std::optional<Bound> bound = subst.lookup(b.side, head.value);
      if (!bound)
        return b;
      std::optional<uint64_t> plus = add(b.plus, bound->plus);
      if (!plus)
        return opaqueBound(b.side);
      b = Bound{bound->nodes, bound->side, *plus};
      continue;
    }
    case TermKind::Sum:
    case TermKind::Literal:
    case TermKind::Constructor:
    case TermKind::Opaque:
      return b;
    case TermKind::Multiple:
      llvm_unreachable("a part of a sum heads no term");
    }
  }
  return b;
}

// Whether level `level` of `side` occurs in `in`, through the bindings: a
// level bound to a term that holds it is a cycle Idris refuses.
bool occurs(const Subst &subst, Side side, uint64_t level, Bound in) {
  llvm::SmallVector<Bound> pending{in};
  while (!pending.empty()) {
    Bound b = pending.pop_back_val();
    for (const TermNode &node : b.nodes) {
      if (node.kind != TermKind::Level)
        continue;
      if (b.side == side && node.value == level)
        return true;
      if (std::optional<Bound> bound = subst.lookup(b.side, node.value))
        pending.push_back(*bound);
    }
  }
  return false;
}

} // namespace

std::optional<Bound> Subst::resolved(Side side, uint64_t level) const {
  std::optional<Bound> bound = lookup(side, level);
  if (!bound)
    return std::nullopt;
  return normal(*this, *bound);
}

namespace {

// A level `v + pv` of a free side against `other`: bind it where the
// language has the term (`v := other - pv` needs `other` to carry at least
// `pv` successors), learn nothing where it does not.
Unified bindLevel(Subst &subst, Bound v, Bound other) {
  const TermNode &head = headOf(v);
  if (isConstant(other)) {
    if (other.plus < v.plus)
      return Unified::Clash;
    subst.bind(v.side, head.value, Bound{{}, other.side, other.plus - v.plus});
    return Unified::Consistent;
  }
  if (headOf(other).kind == TermKind::Level) {
    if (other.plus < v.plus)
      return Unified::Consistent;
    subst.bind(v.side, head.value, Bound{other.nodes, other.side, other.plus - v.plus});
    return Unified::Consistent;
  }
  // A sum: bound where the count peeled off it covers the level's, the
  // sum's own count staying in its nodes. One that holds the level is
  // `v = v + w`, true at `w = 0`, so it learns nothing and is no clash.
  if (headOf(other).kind == TermKind::Sum) {
    if (other.plus < v.plus || occurs(subst, v.side, head.value, other))
      return Unified::Consistent;
    subst.bind(v.side, head.value, Bound{other.nodes, other.side, other.plus - v.plus});
    return Unified::Consistent;
  }
  // A literal or a constructor: a successor of either is no term, so only
  // a level with no count binds to one.
  if (v.plus != 0 || other.plus != 0)
    return Unified::Consistent;
  if (occurs(subst, v.side, head.value, other))
    return Unified::Clash;
  subst.bind(v.side, head.value, other);
  return Unified::Consistent;
}

} // namespace

Unified unify(Subst &subst, Term a, Side sa, Term b, Side sb) {
  llvm::SmallVector<std::pair<Bound, Bound>> pending{{Bound{a.nodes(), sa, 0}, Bound{b.nodes(), sb, 0}}};
  while (!pending.empty()) {
    auto [x, y] = pending.pop_back_val();
    x = normal(subst, x);
    y = normal(subst, y);
    bool xOpaque = !isConstant(x) && headOf(x).kind == TermKind::Opaque;
    bool yOpaque = !isConstant(y) && headOf(y).kind == TermKind::Opaque;
    if (xOpaque || yOpaque) {
      if (subst.opacity() == Opacity::MeetsAnything || (xOpaque && yOpaque))
        continue;
      const Bound &opaque = xOpaque ? x : y;
      const Bound &other = xOpaque ? y : x;
      if (opaque.side != Side::Application)
        continue;
      // Only a free level with no count left on it stays open: it binds to
      // the opaque term, so a second occurrence of it meets that term too.
      if (isConstant(other) || headOf(other).kind != TermKind::Level ||
          !subst.isFree(other.side) || other.plus != 0)
        return Unified::Clash;
      subst.bind(other.side, headOf(other).value, opaque);
      continue;
    }
    if (isConstant(x) && isConstant(y)) {
      if (x.plus != y.plus)
        return Unified::Clash;
      continue;
    }
    bool xLevel = !isConstant(x) && headOf(x).kind == TermKind::Level;
    bool yLevel = !isConstant(y) && headOf(y).kind == TermKind::Level;
    if (xLevel && yLevel && x.side == y.side && headOf(x).value == headOf(y).value) {
      // `v + a = v + b` holds only at a = b; a level one more than itself
      // is the cycle Idris refuses.
      if (x.plus != y.plus)
        return Unified::Clash;
      continue;
    }
    if (xLevel && subst.isFree(x.side)) {
      if (bindLevel(subst, x, y) == Unified::Clash)
        return Unified::Clash;
      continue;
    }
    if (yLevel && subst.isFree(y.side)) {
      if (bindLevel(subst, y, x) == Unified::Clash)
        return Unified::Clash;
      continue;
    }
    // A rigid level, or a level of no free side, stands for a value this
    // unification cannot see: neither a clash nor a binding. Neither is a
    // natural against a constructor or a literal, which no sort puts in
    // one position.
    if (xLevel || yLevel || isConstant(x) || isConstant(y))
      continue;
    const TermNode &hx = headOf(x);
    const TermNode &hy = headOf(y);
    if (hx.kind == TermKind::Literal && hy.kind == TermKind::Literal) {
      if (hx.payload != hy.payload)
        return Unified::Clash;
      continue;
    }
    if (hx.kind != TermKind::Constructor || hy.kind != TermKind::Constructor)
      continue;
    // A null group is the declaration the equation is in.
    mlir::Attribute gx = hx.payload ? hx.payload : subst.ownGroup();
    mlir::Attribute gy = hy.payload ? hy.payload : subst.ownGroup();
    if (gx != gy || hx.member != hy.member || hx.value != hy.value || hx.arity != hy.arity)
      return Unified::Clash;
    llvm::SmallVector<Term> xs = argumentsOf(Term(x.nodes));
    llvm::SmallVector<Term> ys = argumentsOf(Term(y.nodes));
    for (auto [xa, ya] : llvm::reverse(llvm::zip_equal(xs, ys)))
      pending.push_back({Bound{xa.nodes(), x.side, 0}, Bound{ya.nodes(), y.side, 0}});
  }
  return Unified::Consistent;
}

Unified unifyAll(Subst &subst, llvm::ArrayRef<TermNode> application,
                 llvm::ArrayRef<TermNode> equation, size_t count) {
  for (auto [lhs, rhs] : llvm::zip_equal(termsOf(application, count), termsOf(equation, count)))
    if (unify(subst, lhs, Side::Application, rhs, Side::Constructor) == Unified::Clash)
      return Unified::Clash;
  return Unified::Consistent;
}

namespace {

// The level one part of a sum adds, as a term of its side.
Bound partLevel(const Bound &sum, uint32_t part) {
  return Bound{sum.nodes.slice(2 + 2 * static_cast<size_t>(part), 1), sum.side, 0};
}

// `root`, a sum, added to `total` with each level through its bindings, so
// a sum whose levels all became naturals is a natural and one whose levels
// became sums is their sum: a level no binding has stays a level, shifted
// on the constructor side by `shift`; anything bound to no natural makes
// it opaque. Whether a constructor level no binding replaced was added.
// The bindings hold no cycle (a level is never bound to a sum it occurs
// in), so the parts end.
Instance addResolved(const Subst &subst, NatSum &total, Bound root, uint32_t shift) {
  Instance instance = Instance::Determined;
  llvm::SmallVector<std::pair<Bound, uint64_t>> pending{{root, 1}};
  while (!pending.empty()) {
    auto [at, times] = pending.pop_back_val();
    Bound b = normal(subst, at);
    total.addCount(b.plus, times);
    if (isConstant(b))
      continue;
    const TermNode &head = headOf(b);
    switch (head.kind) {
    case TermKind::Level:
      if (b.side == Side::Constructor)
        instance = Instance::Undetermined;
      total.addLevel(static_cast<uint32_t>(head.value) + (b.side == Side::Constructor ? shift : 0),
                     times);
      continue;
    case TermKind::Sum:
      total.addCount(head.value, times);
      for (uint32_t part = 0; part < head.arity; ++part) {
        std::optional<uint64_t> occurs =
            multiply(b.nodes[1 + 2 * static_cast<size_t>(part)].value, times);
        if (!occurs) {
          total.forget();
          break;
        }
        pending.push_back({partLevel(b, part), *occurs});
      }
      continue;
    case TermKind::Literal:
    case TermKind::Constructor:
    case TermKind::Opaque:
      total.forget();
      continue;
    case TermKind::Natural:
    case TermKind::Successor:
    case TermKind::Multiple:
      // `normal` peels the first two, and the third heads no term.
      continue;
    }
  }
  return instance;
}

} // namespace

// Preorder, from a stack: a constructor's head is written, then its
// arguments, each a view waiting its turn, so a deep term is written with
// no recursion on its depth.
Instance Subst::write(TermWriter &out, Term term, Side side, uint32_t shift) const {
  Instance instance = Instance::Determined;
  llvm::SmallVector<Bound> pending{Bound{term.nodes(), side, 0}};
  while (!pending.empty()) {
    Bound b = normal(*this, pending.pop_back_val());
    if (isConstant(b)) {
      out.natural(b.plus);
      continue;
    }
    const TermNode &head = headOf(b);
    switch (head.kind) {
    case TermKind::Level:
      if (b.side == Side::Constructor)
        instance = Instance::Undetermined;
      out.level(static_cast<uint32_t>(head.value) + (b.side == Side::Constructor ? shift : 0),
                b.plus);
      continue;
    case TermKind::Sum: {
      NatSum total;
      if (addResolved(*this, total, b, shift) == Instance::Undetermined)
        instance = Instance::Undetermined;
      out.sum(total);
      continue;
    }
    case TermKind::Opaque:
      out.opaque();
      continue;
    case TermKind::Literal:
      if (b.plus > 0)
        out.opaque();
      else
        out.literal(head.payload);
      continue;
    case TermKind::Constructor: {
      if (b.plus > 0) {
        out.opaque();
        continue;
      }
      out.constructor(head.payload ? head.payload : own, head.member, head.value, head.arity);
      llvm::SmallVector<Term> args = argumentsOf(Term(b.nodes));
      for (Term arg : llvm::reverse(args))
        pending.push_back(Bound{arg.nodes(), b.side, 0});
      continue;
    }
    case TermKind::Natural:
    case TermKind::Successor:
    case TermKind::Multiple:
      // `normal` peels the first two, and the third heads no term.
      continue;
    }
  }
  return instance;
}

} // namespace idr::families
