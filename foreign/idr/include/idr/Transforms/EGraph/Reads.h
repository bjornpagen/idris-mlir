// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a skeleton rule reads of one function's e-graph (OperandFacts),
// answered inline from the engine's tables alone, so that a rule's
// library, the dialect's at the bottom among them, needs no symbol of the
// engine's: the engine calls the rules, and the rules read only headers.
// A rule reads once the graph is settled, where every value's class is its
// root, so each answer is a load or two. Engine.h includes this once its
// tables are declared.
#ifndef IDR_TRANSFORMS_EGRAPH_READS_H
#define IDR_TRANSFORMS_EGRAPH_READS_H

#include "idr/Transforms/EGraph/Engine.h"

namespace idr::egraph::detail {

inline const Class &Function::classOfValue(mlir::Value value) const {
  return at(*classOf[numbering.at(value)]);
}

inline Cost Function::costOf(mlir::Value value) const {
  return cost[classOf[numbering.at(value)]->index()];
}

// Whether `placed` is `scope` or holds it.
inline bool Function::visible(RegionId placed, RegionId scope) const {
  std::optional<RegionId> at = scope;
  while (at && this->at(*at).depth >= this->at(placed).depth) {
    if (*at == placed)
      return true;
    at = this->at(*at).parent;
  }
  return false;
}

inline std::optional<RegionId> Function::outerOf(RegionId a, RegionId b) const {
  if (visible(a, b))
    return a;
  if (visible(b, a))
    return b;
  return std::nullopt;
}

// Regions a node's operands can be computed in each hold its own place, so
// they nest wherever it was written or a rule built it, and it can be
// computed in the innermost.
inline std::optional<RegionId> Function::needs(const Node &node) const {
  RegionId body(0);
  RegionId inner = match(
      node.what, [](const node::Leaf &leaf) { return leaf.home; },
      [&](const OneOf<node::Input, node::Built, node::Held, node::Integer,
                      node::Known> auto &) { return body; });
  for (ClassId operand : childrenOf(node)) {
    RegionId there = at(forest.rootOf(operand)).reach;
    if (!outerOf(inner, there))
      return std::nullopt;
    if (at(there).depth > at(inner).depth)
      inner = there;
  }
  return inner;
}

// The first member of the value's class, in member order, that is an op of
// the input of class `OpT` and can be computed wherever the class is used:
// a member computable only inside the class's reach may stand where the
// rule's root does not see it. An op a rule built has no op of the input
// to read, and a leaf is the value a skeleton op or a region gives.
template <class OpT>
OpT Function::memberBuiltBy(mlir::Value value) const {
  const Class &cls = at(*classOf[numbering.at(value)]);
  for (std::optional<NodeId> member = cls.first; member; member = nextMember[member->index()]) {
    const Node &node = at(*member);
    if (needs(node) != cls.reach)
      continue;
    OpT op = match(
        node.what, [](const node::Input &input) { return llvm::dyn_cast<OpT>(input.origin); },
        [](const OneOf<node::Built, node::Leaf, node::Held, node::Integer,
                       node::Known> auto &) { return OpT(); });
    if (op)
      return op;
  }
  return OpT();
}

// The constant the value's class is, as its facts say it: an integer, the
// one value of its interval, or the constant it holds, borrowed from the
// class, whichever member said it.
inline std::optional<KnownConstant> Function::knownOf(mlir::Value value) const {
  const Facts &facts = classOfValue(value).facts;
  if (std::optional<llvm::APInt> integer = facts.integer())
    return KnownConstant(std::move(*integer));
  if (!facts.constant)
    return std::nullopt;
  return match(
      *facts.constant,
      [](const Text &text) -> std::optional<KnownConstant> { return KnownConstant(&text); },
      [](const Real &real) -> std::optional<KnownConstant> { return KnownConstant(real); },
      [](const Big &big) -> std::optional<KnownConstant> { return KnownConstant(&big); },
      [](const Data &) -> std::optional<KnownConstant> { return std::nullopt; });
}

// The constructor of the constructor constant the value's class is, held or
// built, whichever member said it.
inline std::optional<Tag> Function::constructorOf(mlir::Value value) const {
  const Facts &facts = classOfValue(value).facts;
  const Data *data = facts.constant ? std::get_if<Data>(&*facts.constant) : nullptr;
  return data ? data->tag() : std::nullopt;
}

// The constant an op of the input in the value's class holds, as it holds
// it, from a member: a constant the graph computed is a value, and no op
// holds it.
inline mlir::Attribute Function::heldBy(mlir::Value value) const {
  const Class &cls = at(*classOf[numbering.at(value)]);
  for (std::optional<NodeId> member = cls.first; member; member = nextMember[member->index()]) {
    mlir::Attribute held = match(
        at(*member).what, [](const node::Held &constant) { return constant.value; },
        [](const OneOf<node::Input, node::Built, node::Leaf, node::Integer, node::Known> auto &) {
          return mlir::Attribute();
        });
    if (held)
      return held;
  }
  return {};
}

// The guard's own decision of its operands' classes: its op's, from the
// table of guards by op class, which holds every op of the guard interface,
// the one dispatch MLIR's open op set leaves to run time.
inline numeric::Known Function::decisionOf(GuardOpInterface guard) const {
  std::optional<Decision> decides = kinds.of(guard.getOperation()).decision;
  assert(decides && "every op of the guard interface has its decision in the table");
  llvm::SmallVector<const Class *, 3> operands;
  for (mlir::Value operand : guard->getOperands())
    operands.push_back(&classOfValue(operand));
  return (*decides)(operands);
}

} // namespace idr::egraph::detail

namespace idr::egraph {

inline std::optional<KnownConstant> OperandFacts::constant(mlir::Value value) const {
  return function.knownOf(value);
}

inline std::optional<Tag> OperandFacts::constructorTag(mlir::Value value) const {
  return function.constructorOf(value);
}

inline mlir::Attribute OperandFacts::held(mlir::Value value) const {
  return function.heldBy(value);
}

inline numeric::Known OperandFacts::decision(GuardOpInterface guard) const {
  return function.decisionOf(guard);
}

inline std::optional<mlir::ConstantIntRanges> OperandFacts::range(mlir::Value value) const {
  return function.classOfValue(value).facts.range;
}

template <class OpT>
OpT OperandFacts::builtBy(mlir::Value value) const {
  return function.memberBuiltBy<OpT>(value);
}

inline Cost OperandFacts::cost(mlir::Value value) const { return function.costOf(value); }

} // namespace idr::egraph

#endif // IDR_TRANSFORMS_EGRAPH_READS_H
