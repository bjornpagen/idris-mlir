// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The specification's rules, read where the compiler is built: the
// generated tables, the kinds they name, the matcher and the builder of a
// right side over them, the interval a built node's kind gives it, and the
// dispatch of the hand skeleton rules. A pattern is a constant of the
// specification, so the matcher's descent through one is bounded by the
// specification, never by the input.
//
// The skeleton rules are each area's hand classes, declared where the
// specification names them; the generated tables include every header
// that declares one, and the classes of the upstream ops they admit are
// declared by those ops' dialects, included first.
#include "idr/Transforms/EGraph/Engine.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <span>
#include <utility>

#include "idr/IR/Generated/Rewrites.h.inc"

using namespace mlir;

namespace idr::egraph::detail {

std::uint32_t nodesPerOp() { return generated::nodesPerOp; }

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
std::optional<Decided> decideAll(table::RuleList<Rs...>, Operation *op,
                                 const OperandFacts &facts) {
  std::optional<Decided> decided;
  std::uint32_t index = 0;
  auto ask = [&]<class R>() {
    if (!decided)
      if (auto root = dyn_cast<typename R::Root>(op))
        if (std::optional<Edit> edit = R::decide(root, facts))
          decided = Decided{std::move(*edit), index};
    ++index;
  };
  (ask.template operator()<Rs>(), ...);
  return decided;
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

bool beforeId(TypeID a, TypeID b) { return a.getAsOpaquePointer() < b.getAsOpaquePointer(); }

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
  llvm::sort(out.byTypeId,
             [](const auto &a, const auto &b) { return beforeId(a.first, b.first); });
  return out;
}

std::optional<Decided> Function::decideSkeleton(Operation *op, const OperandFacts &facts) const {
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
    std::optional<APInt> value = this->at(cls).facts.integer();
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
  std::optional<std::uint16_t> kind =
      match(node.what, [](const node::Input &op) { return op.kind; },
            [](const node::Built &op) { return std::optional(op.kind); },
            []<Atom N>(const N &) { return std::optional<std::uint16_t>(); });
  if (kind != pattern.op || node.children.count != pattern.arity)
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
    return known.integer().has_value();
  case table::ConditionKind::PowerOfTwo: {
    std::optional<APInt> value = known.integer();
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

// What a node a right side built knows: the interval its kind's range
// function gives its operands' intervals, an operand with none its type's
// whole width (a kind with a range function takes integers), where the
// kind has one. No op is made to fold it: over constants, the interval's
// one value is the integer it is.
Facts Function::factsOf(const node::Built &op, Type type,
                        std::span<const ClassId> operands) const {
  const std::optional<table::IntRangeFn> &range = generated::intRanges[op.kind];
  if (!range)
    return {};
  SmallVector<ConstantIntRanges, 4> inputs;
  for (ClassId operand : operands) {
    const Class &cls = at(operand);
    inputs.push_back(cls.facts.range ? *cls.facts.range
                                     : ConstantIntRanges::maxRange(
                                           ConstantIntRanges::getStorageBitwidth(cls.type)));
  }
  return {(*range)(inputs, type), Attribute()};
}

// The right side's subtree at `at`, built bottom-up: a variable is its
// class; a literal the integer the dialect reads it as at the type its
// place takes, a value the write-back makes an attribute, and none where it
// is no value of that type or the type has no integer form, so the rule
// does not apply there; a node made over its operands' classes, of `type`
// at the top and of its first operand's type below (the arithmetic a rule
// builds keeps its operands' type).
std::optional<ClassId> Function::buildSide(const table::Rule &rule, const Bindings &bindings,
                                           std::uint32_t &at, Type type) {
  const table::PatternNode &pattern = generated::patterns[at++];
  switch (pattern.kind) {
  case table::PatternKind::Var:
    return bindings.vars[pattern.var];
  case table::PatternKind::Literal: {
    std::optional<APInt> value = integerAt(type, pattern.literal);
    if (!value)
      return std::nullopt;
    return integer(*value, type);
  }
  case table::PatternKind::Node: {
    SmallVector<ClassId, 4> operands;
    for (std::uint8_t i = 0; i < pattern.arity; ++i) {
      Type place = operands.empty() ? type : this->at(operands.front()).type;
      std::optional<ClassId> operand = buildSide(rule, bindings, at, place);
      if (!operand)
        return std::nullopt;
      operands.push_back(*operand);
    }
    // A kind whose dialect the context has not loaded is no op to build.
    const std::optional<RegisteredOperationName> &name = kinds.names[pattern.op];
    if (!name)
      return std::nullopt;
    return insert(node::Built{pattern.op, *name}, type, operands);
  }
  }
  return std::nullopt;
}

// A right side built grows the node table, which moves the node, so the
// node is read again by its id; `op` is the caller's copy.
std::optional<ClassId> Function::rewrite(NodeId made, const node::Input &op, Type type) {
  // An op no pattern names roots no rule.
  if (!op.kind)
    return std::nullopt;
  for (std::uint32_t r = generated::rulesOfKind[*op.kind];
       r < generated::rulesOfKind[*op.kind + 1]; ++r) {
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
    std::optional<ClassId> side = buildSide(rule, bindings, at, type);
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
