// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The specification's rules, read where the compiler is built: the
// generated tables, the kinds they name, the matcher and the builder of a
// right side over them, and the dispatch of the hand skeleton rules. A
// pattern is a constant of the specification, so the matcher's descent
// through one is bounded by the specification, never by the input.
//
// The skeleton rules are each area's hand classes, declared where the
// specification names them; the generated tables include every header
// that declares one, and the classes of the upstream ops they admit are
// declared by those ops' dialects, included first.
#include "idr/Transforms/EGraph/Engine.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/MathExtras.h"

#include <algorithm>
#include <span>
#include <tuple>
#include <utility>

#include "idr/IR/Generated/Rewrites.h.inc"

using namespace mlir;

namespace idr::egraph {

std::uint32_t nodesPerOp() { return generated::nodesPerOp; }

} // namespace idr::egraph

namespace idr::egraph::detail {

namespace {

template <class... Rs>
constexpr bool everySkeletonRule(table::RuleList<Rs...>) {
  return (SkeletonRule<Rs> && ...);
}
static_assert(everySkeletonRule(generated::SkeletonRules{}),
              "every skeleton rule the specification names meets the engine's concept");

template <class... Ops>
void listKinds(table::OpList<Ops...>, MLIRContext *context, Kinds &out) {
  std::uint16_t kind = 0;
  (
      [&] {
        out.byTypeId.emplace_back(TypeID::get<Ops>(), kind);
        out.names.push_back(RegisteredOperationName::lookup(TypeID::get<Ops>(), context));
        ++kind;
      }(),
      ...);
}

template <class... Rs>
Fate decideAll(table::RuleList<Rs...>, Operation *op, const OperandFacts &facts) {
  Fate fate = Kept{};
  std::uint32_t index = 0;
  auto ask = [&]<class R>() {
    if (std::holds_alternative<Kept>(fate))
      if (auto root = dyn_cast<typename R::Root>(op))
        if (std::optional<Edit> edit = R::decide(root, facts))
          fate = Decided{std::move(*edit), index};
    ++index;
  };
  (ask.template operator()<Rs>(), ...);
  return fate;
}

template <class... Rs>
void rewriteOne(table::RuleList<Rs...>, std::uint32_t rule, Operation *op, const Rewrite &rewrite,
                RewriterBase &rewriter) {
  std::uint32_t index = 0;
  auto run = [&]<class R>() {
    if (index++ == rule)
      R::rewrite(cast<typename R::Root>(op), rewrite, rewriter);
  };
  (run.template operator()<Rs>(), ...);
}

// The integer a constant is: an integer's bits at its width, read signed,
// or a big's value. Any other constant is no integer.
std::optional<APInt> integerOf(Attribute constant) {
  if (auto integer = dyn_cast_if_present<IntegerAttr>(constant))
    return integer.getValue();
  if (auto big = dyn_cast_if_present<BigAttr>(constant))
    return big.getValue();
  return std::nullopt;
}

// The literal `value` as a constant of `type`, the type of the place it
// fills: a big, a natural where it is not negative, or an integer of the
// type's width where it fits; none at any other type, so the rule does not
// apply there.
Attribute literalOf(Type type, std::int64_t value) {
  Type plain = unrestricted(type);
  if (isa<BigType>(plain) || (isa<NatType>(plain) && value >= 0))
    return BigAttr::get(type.getContext(),
                        APInt(64, static_cast<std::uint64_t>(value), /*isSigned=*/true));
  if (!plain.isIntOrIndex())
    return Attribute();
  unsigned width =
      plain.isIndex() ? IndexType::kInternalStorageBitWidth : plain.getIntOrFloatBitWidth();
  if (!llvm::isIntN(width, value))
    return Attribute();
  return IntegerAttr::get(plain, value);
}

} // namespace

std::optional<std::uint16_t> Kinds::kindOf(Operation *op) const {
  TypeID id = op->getName().getTypeID();
  auto it = llvm::lower_bound(byTypeId, std::pair(id, std::uint16_t(0)),
                              [](const auto &a, const auto &b) {
                                return a.first.getAsOpaquePointer() < b.first.getAsOpaquePointer();
                              });
  if (it == byTypeId.end() || it->first != id)
    return std::nullopt;
  return it->second;
}

Kinds makeKinds(MLIRContext *context) {
  Kinds out;
  listKinds(generated::Kinds{}, context, out);
  llvm::sort(out.byTypeId, [](const auto &a, const auto &b) {
    return a.first.getAsOpaquePointer() < b.first.getAsOpaquePointer();
  });
  return out;
}

Fate Function::decideSkeleton(Operation *op, const OperandFacts &facts) const {
  return decideAll(generated::SkeletonRules{}, op, facts);
}

void Function::rewriteSkeleton(const Pending &pending, RewriterBase &rewriter) {
  rewriteOne(generated::SkeletonRules{}, pending.rule, pending.root, pending.rewrite, rewriter);
}

//===----------------------------------------------------------------------===//
// Matching
//===----------------------------------------------------------------------===//

// The pattern at `at` against class `cls`: a variable binds it, or meets
// the class it bound before (a repeated variable is an equality); a literal
// is the class's constant; a node pattern is a member of the class of that
// kind and arity whose operands match in turn. The index after the
// pattern's subtree on a match.
std::optional<std::uint32_t> Function::matchClass(std::uint32_t at, ClassId cls,
                                                  Bindings &bindings) const {
  const table::PatternNode &pattern = generated::patterns[at];
  switch (pattern.kind) {
  case table::PatternKind::Var: {
    std::optional<ClassId> &bound = bindings.vars[pattern.var];
    if (bound && *bound != cls)
      return std::nullopt;
    bound = cls;
    return at + 1;
  }
  case table::PatternKind::Literal: {
    std::optional<APInt> value = integerOf(this->at(cls).facts.constant);
    if (!value || value->getSignificantBits() > 64 || value->getSExtValue() != pattern.literal)
      return std::nullopt;
    return at + 1;
  }
  case table::PatternKind::Node:
    for (NodeId member : membersOf(this->at(cls))) {
      Bindings tried = bindings;
      if (std::optional<std::uint32_t> next = matchNode(at, member, tried)) {
        bindings = std::move(tried);
        return next;
      }
    }
    return std::nullopt;
  }
  return std::nullopt;
}

std::optional<std::uint32_t> Function::matchNode(std::uint32_t at, NodeId n,
                                                 Bindings &bindings) const {
  const table::PatternNode &pattern = generated::patterns[at];
  const Node &node = this->at(n);
  const auto *op = std::get_if<node::Op>(&node.what);
  if (!op || op->kind != pattern.op || node.children.count != pattern.arity)
    return std::nullopt;
  std::uint32_t next = at + 1;
  for (ClassId operand : childrenOf(node)) {
    std::optional<std::uint32_t> after = matchClass(next, operand, bindings);
    if (!after)
      return std::nullopt;
    next = *after;
  }
  return next;
}

// A side condition, read off the bound class's analyses. Clean holds of
// every class the e-graph holds: a node floats only where nothing orders
// it, a call only where its row carries neither crash nor divergence, and
// a leaf's maker stays in the skeleton whatever a rule drops.
bool Function::holds(const table::Condition &condition, const Bindings &bindings) const {
  const Facts &known = at(*bindings.vars[condition.var]).facts;
  switch (condition.kind) {
  case table::ConditionKind::IsConstant:
    return static_cast<bool>(known.constant);
  case table::ConditionKind::PowerOfTwo: {
    std::optional<APInt> value = integerOf(known.constant);
    return value && value->isStrictlyPositive() && value->isPowerOf2();
  }
  case table::ConditionKind::InRange:
    return known.range && known.range->smin().getSignificantBits() <= 64 &&
           known.range->smax().getSignificantBits() <= 64 &&
           known.range->smin().getSExtValue() >= condition.lo &&
           known.range->smax().getSExtValue() <= condition.hi;
  case table::ConditionKind::Clean:
    return true;
  }
  return false;
}

// The right side's subtree at `at`, built bottom-up: a variable is its
// class; a literal a constant of the type its place takes, an integer or a
// big as that type holds one, materialized by the dialect of the op the
// rule is rooted at; a node made over its operands' classes, of `type` at
// the top and of its first operand's type below (the arithmetic a rule
// builds keeps its operands' type). Its insertion runs no rules.
std::optional<ClassId> Function::buildSide(const table::Rule &rule, const Bindings &bindings,
                                           std::uint32_t &at, Type type, Dialect *dialect) {
  const table::PatternNode &pattern = generated::patterns[at++];
  switch (pattern.kind) {
  case table::PatternKind::Var:
    return bindings.vars[pattern.var];
  case table::PatternKind::Literal: {
    Attribute value = literalOf(type, pattern.literal);
    if (!value)
      return std::nullopt;
    return constant(value, type, dialect);
  }
  case table::PatternKind::Node: {
    SmallVector<ClassId, 4> operands;
    for (std::uint8_t i = 0; i < pattern.arity; ++i) {
      Type place = operands.empty() ? type : this->at(operands.front()).type;
      std::optional<ClassId> operand = buildSide(rule, bindings, at, place, dialect);
      if (!operand)
        return std::nullopt;
      operands.push_back(*operand);
    }
    const std::optional<RegisteredOperationName> &name = kinds.names[pattern.op];
    if (!name)
      return std::nullopt;
    return insert(*name, pattern.op, nullptr, Identity::Shared, type, operands, Rules::Skip);
  }
  }
  return std::nullopt;
}

std::optional<ClassId> Function::rewrite(NodeId made) {
  // Copied out first: a right side built grows the node table, which moves
  // the node, and a later rule is still tried when that side does not apply.
  auto [kind, type, dialect] = [&] {
    const Node &node = at(made);
    const auto &op = std::get<node::Op>(node.what);
    return std::tuple(op.kind, node.type, op.name.getDialect());
  }();
  if (!kind)
    return std::nullopt;
  for (std::uint32_t r = generated::rulesOfKind[*kind]; r < generated::rulesOfKind[*kind + 1];
       ++r) {
    const table::Rule &rule = generated::rules[r];
    Bindings bindings;
    bindings.vars.resize(rule.vars);
    if (!matchNode(rule.lhs, made, bindings))
      continue;
    std::span<const table::Condition> conditions =
        std::span<const table::Condition>(generated::conditions)
            .subspan(rule.conditions, rule.conditionCount);
    if (!llvm::all_of(conditions, [&](const table::Condition &c) { return holds(c, bindings); }))
      continue;
    std::uint32_t at = rule.rhs;
    std::optional<ClassId> side = buildSide(rule, bindings, at, type, dialect);
    // A specification sort is coarser than an MLIR type, which holds index
    // terms: a right side whose class is of another type here does not
    // apply here, since no rewrite changes a value's type.
    if (!side || this->at(*side).type != type)
      continue;
    return side;
  }
  return std::nullopt;
}

} // namespace idr::egraph::detail
