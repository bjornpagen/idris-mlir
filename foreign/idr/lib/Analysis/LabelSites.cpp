// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The graph of the label solve, built by one walk of the module: each op's
// edges as it declares them (flowEdgesOf), a node for each point an edge
// names, and the constants' parts expanded where they are held. A
// function's parameter is its entry block's argument, one node.

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::labels {

namespace {

// The value a parameter of a function is: its entry block's argument. The
// world is closed, so every function named has a body.
Value parameterValue(const SymbolTable &table, FlatSymbolRefAttr function, unsigned index) {
  auto fn = table.lookup<FuncOp>(function.getAttr());
  assert(fn && !fn.getBody().empty() && "a label is a function of the module with a body");
  return fn.getArgument(index);
}

std::tuple<unsigned, Type, unsigned, unsigned> anchorKey(const FlowAnchor &anchor) {
  return {static_cast<unsigned>(anchor.kind), anchor.type, anchor.ctor, anchor.field};
}

} // namespace

Node Graph::fresh() {
  Node node = static_cast<Node>(parents.size());
  parents.push_back(node);
  classes.emplace_back();
  return node;
}

std::optional<Node> Graph::lookup(const FlowPoint &point) const {
  switch (point.kind) {
  case FlowPoint::Kind::Operand:
    return lookup(FlowPoint::of(point.operand->get()));
  case FlowPoint::Kind::Value:
    if (auto it = values.find(point.value); it != values.end())
      return it->second;
    return std::nullopt;
  case FlowPoint::Kind::Parameter:
    return lookup(FlowPoint::of(parameterValue(table, point.function, point.index)));
  case FlowPoint::Kind::Result:
    if (auto it = results.find({point.function.getAttr(), point.index}); it != results.end())
      return it->second;
    return std::nullopt;
  case FlowPoint::Kind::Anchor:
    if (auto it = anchors.find(anchorKey(point.anchor)); it != anchors.end())
      return it->second;
    return std::nullopt;
  }
  llvm_unreachable("every kind of point is listed");
}

Node Graph::nodeOf(const FlowPoint &point) {
  switch (point.kind) {
  case FlowPoint::Kind::Operand:
    return nodeOf(FlowPoint::of(point.operand->get()));
  case FlowPoint::Kind::Value: {
    auto [it, made] = values.try_emplace(point.value, 0);
    if (made)
      it->second = fresh();
    return it->second;
  }
  case FlowPoint::Kind::Parameter:
    return nodeOf(FlowPoint::of(parameterValue(table, point.function, point.index)));
  case FlowPoint::Kind::Result: {
    auto [it, made] = results.try_emplace({point.function.getAttr(), point.index}, 0);
    if (made)
      it->second = fresh();
    return it->second;
  }
  case FlowPoint::Kind::Anchor: {
    auto [it, made] = anchors.try_emplace(anchorKey(point.anchor), 0);
    if (made)
      it->second = fresh();
    return it->second;
  }
  }
  llvm_unreachable("every kind of point is listed");
}

// The carrier of what is held at a point: its type without its grade.
Type Graph::carrierOf(const FlowPoint &point) const {
  switch (point.kind) {
  case FlowPoint::Kind::Operand:
    return unrestricted(point.operand->get().getType());
  case FlowPoint::Kind::Value:
    return unrestricted(point.value.getType());
  case FlowPoint::Kind::Parameter:
    return unrestricted(parameterValue(table, point.function, point.index).getType());
  case FlowPoint::Kind::Result: {
    auto fn = table.lookup<FuncOp>(point.function.getAttr());
    return unrestricted(fn.getResultTypes()[point.index]);
  }
  case FlowPoint::Kind::Anchor:
    switch (point.anchor.kind) {
    case FlowAnchor::Kind::Field:
      return unrestricted(
          cast<DataType>(point.anchor.type).getCtor(point.anchor.ctor).fields[point.anchor.field]);
    case FlowAnchor::Kind::Elements:
      return point.anchor.type;
    case FlowAnchor::Kind::Forced:
      return unrestricted(cast<LazyType>(point.anchor.type).getValue());
    }
  }
  llvm_unreachable("every kind of point is listed");
}

std::optional<FlowPoint> Graph::sinkOf(OpOperand &operand) const {
  if (auto it = sinks.find(&operand); it != sinks.end())
    return it->second;
  return std::nullopt;
}

void Graph::walk(Operation *module) {
  FlowEdges edges;
  module->walk([&](Operation *op) {
    flowEdgesOf(op, edges);
    for (const FlowEdges::Edge &edge : edges.edges())
      add(edge);
    edges.clear();
  });
}

void Graph::add(const FlowEdges::Edge &edge) {
  switch (edge.kind) {
  case FlowEdges::Edge::Kind::Flow:
    return flow(edge.from, edge.to);
  case FlowEdges::Edge::Kind::Unify:
    return unify(nodeOf(edge.from), nodeOf(edge.to));
  case FlowEdges::Edge::Kind::Source: {
    std::uint32_t id = labelId(edge.label);
    return addLabels(nodeOf(edge.to), intern(id));
  }
  case FlowEdges::Edge::Kind::Constant:
    return expand(edge.constant, edge.to, carrierOf(edge.to));
  case FlowEdges::Edge::Kind::Dispatch: {
    auto call = cast<CallOpInterface>(edge.call);
    Node callee = nodeOf(FlowPoint::of(cast<Value>(call.getCallableForCallee())));
    unsigned index = static_cast<unsigned>(dispatches.size());
    dispatches.push_back({call, {}});
    dispatchList.push_back(edge.call);
    classes[find(callee)].dispatches.push_back(index);
    // The labels already there are run now; those that come later, as
    // they come.
    return fire(index, classes[find(callee)].set);
  }
  }
}

// An operand moves its value into one point: a second edge from it joins
// its target to the first, so the operand has one slot to be moved into.
void Graph::flow(const FlowPoint &from, const FlowPoint &to) {
  if (from.kind == FlowPoint::Kind::Operand) {
    auto [it, first] = sinks.try_emplace(from.operand, to);
    if (!first)
      return unify(nodeOf(it->second), nodeOf(to));
  }
  // Every flow has a value at one end, an operand or a result or argument,
  // whose type is the edge's carrier.
  Type carrier = from.kind == FlowPoint::Kind::Operand || from.kind == FlowPoint::Kind::Value
                     ? carrierOf(from)
                     : carrierOf(to);
  link(nodeOf(from), nodeOf(to), isLazyType(carrier));
}

// Whether `part` of a constant holds a closure, each part answered once.
bool Graph::holdsClosure(Attribute part) {
  auto closure = dyn_cast<ClosureAttr>(part);
  auto con = dyn_cast<ConAttr>(part);
  if (!closure && !con)
    return false;
  if (auto it = holding.find(part); it != holding.end())
    return it->second;
  bool found = static_cast<bool>(closure);
  if (con)
    eachField(con, [&](Attribute field, unsigned) { found = holdsClosure(field) || found; });
  holding[part] = found;
  return found;
}

// A constant part held at a point of carrier `carrier`: a closure is its
// label there, its captures at the label's parameters; a suspension is that
// too, and its label returns into the forced state of its type; a
// constructor holds each field at its field's anchor. A shared part at one
// point is expanded once.
void Graph::expand(Attribute part, const FlowPoint &at, Type carrier) {
  if (!holdsClosure(part))
    return;
  Node node = nodeOf(at);
  if (!expanded.insert({part, node}).second)
    return;
  if (auto closure = dyn_cast<ClosureAttr>(part)) {
    FlatSymbolRefAttr label = closure.getCallee();
    std::uint32_t id = labelId(label);
    addLabels(node, intern(id));
    auto fn = table.lookup<FuncOp>(label.getAttr());
    for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
      expand(capture, FlowPoint::parameter(label, static_cast<unsigned>(i)),
             unrestricted(fn.getArgumentTypes()[i]));
    if (isa<LazyType>(carrier))
      unify(nodeOf(FlowPoint::result(label, 0)),
            nodeOf(FlowPoint::of(FlowAnchor::forcedOf(carrier))));
    return;
  }
  auto con = cast<ConAttr>(part);
  DataType data = con.getData();
  std::optional<unsigned> tag = data.getTag(con.getCtor().getValue());
  assert(tag && "a constant's constructor is one of its type's");
  ArrayRef<Type> fields = data.getCtor(*tag).fields;
  eachField(con, [&](Attribute field, unsigned i) {
    expand(field, FlowPoint::of(FlowAnchor::fieldOf(data, *tag, i)), unrestricted(fields[i]));
  });
}

} // namespace idr::labels
