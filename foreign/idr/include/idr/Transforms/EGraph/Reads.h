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

// The op of the input the value's chosen member is, if it is one.
inline mlir::Operation *Function::originOf(mlir::Value value) const {
  const std::optional<NodeId> &chosen = best[classOf[numbering.at(value)]->index()];
  return match(at(*chosen).what, [](const node::Input &op) { return op.origin; },
               [](const node::Built &) -> mlir::Operation * { return nullptr; },
               []<Atom N>(const N &) -> mlir::Operation * { return nullptr; });
}

} // namespace idr::egraph::detail

namespace idr::egraph {

inline mlir::Attribute OperandFacts::constant(mlir::Value value) const {
  return function.classOfValue(value).facts.attribute;
}

inline std::optional<mlir::ConstantIntRanges> OperandFacts::range(mlir::Value value) const {
  return function.classOfValue(value).facts.range;
}

inline mlir::Operation *OperandFacts::origin(mlir::Value value) const {
  return function.originOf(value);
}

inline Cost OperandFacts::cost(mlir::Value value) const { return function.costOf(value); }

} // namespace idr::egraph

#endif // IDR_TRANSFORMS_EGRAPH_READS_H
