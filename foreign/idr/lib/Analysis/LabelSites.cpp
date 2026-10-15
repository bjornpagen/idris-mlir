// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The graph of the label solve, built by one walk of the program: each op's
// edges as it declares them (flowEdgesOf), those that carry a label kept, a
// node for each point a kept edge names, and the constants' parts expanded
// where they are held. A function's parameter is its entry block's
// argument, one node; a part of a value is its anchor's node.

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
  assert(fn && !fn.getBody().empty() && "a label is a function of the program with a body");
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

std::optional<Node> Graph::lookup(const FlowAnchor &anchor) const {
  if (auto it = anchors.find(anchorKey(anchor)); it != anchors.end())
    return it->second;
  return std::nullopt;
}

std::optional<Node> Graph::lookup(const FlowPoint &point) const {
  switch (point.kind) {
  case FlowPoint::Kind::Operand:
  case FlowPoint::Kind::Value:
    if (auto it = values.find(point.getValue()); it != values.end())
      return it->second;
    return std::nullopt;
  case FlowPoint::Kind::Part:
    return lookup(point.anchor);
  case FlowPoint::Kind::Parameter:
    return lookup(FlowPoint::of(parameterValue(table, point.function, point.index)));
  case FlowPoint::Kind::Result:
    if (auto it = results.find({point.function.getAttr(), point.index}); it != results.end())
      return it->second;
    return std::nullopt;
  }
  llvm_unreachable("every kind of point is listed");
}

Node Graph::nodeOf(const FlowAnchor &anchor) {
  auto [it, made] = anchors.try_emplace(anchorKey(anchor), 0);
  if (made)
    it->second = fresh();
  return it->second;
}

Node Graph::nodeOf(const FlowPoint &point) {
  switch (point.kind) {
  case FlowPoint::Kind::Operand:
  case FlowPoint::Kind::Value: {
    auto [it, made] = values.try_emplace(point.getValue(), 0);
    if (made)
      it->second = fresh();
    return it->second;
  }
  case FlowPoint::Kind::Part:
    return nodeOf(point.anchor);
  case FlowPoint::Kind::Parameter:
    return nodeOf(FlowPoint::of(parameterValue(table, point.function, point.index)));
  case FlowPoint::Kind::Result: {
    auto [it, made] = results.try_emplace({point.function.getAttr(), point.index}, 0);
    if (made)
      it->second = fresh();
    return it->second;
  }
  }
  llvm_unreachable("every kind of point is listed");
}

std::optional<FlowPoint> Graph::sinkOf(OpOperand &operand) const {
  if (auto it = sinks.find(&operand); it != sinks.end())
    return it->second;
  return std::nullopt;
}

void Graph::walk(Operation *program) {
  FlowEdges edges;
  program->walk([&](Operation *op) {
    flowEdgesOf(op, edges);
    for (const FlowEdges::Edge &edge : edges.edges())
      add(op, edge);
    edges.clear();
  });
}

// A flow that carries no label, and what only a reference does (a fresh
// cell, a reference given up), moves no label and makes no node. A source,
// a unification and a dispatch are of labels alone. A constant is looked
// into whatever carrier holds it: a constructor of any data type may hold a
// closure in a field.
void Graph::add(Operation *op, const FlowEdges::Edge &edge) {
  switch (edge.kind) {
  case FlowEdges::Edge::Kind::Flow:
    if (!edge.carriesAny(Carriers::labels()))
      return;
    return flow(op, edge.from, edge.to, edge.carries(Carrier::Suspension));
  case FlowEdges::Edge::Kind::Unify:
    return unify(nodeOf(edge.from), nodeOf(edge.to));
  case FlowEdges::Edge::Kind::Source: {
    Label id = labelId(edge.label);
    return addLabels(nodeOf(edge.to), id);
  }
  case FlowEdges::Edge::Kind::Fresh:
  case FlowEdges::Edge::Kind::Release:
    return;
  case FlowEdges::Edge::Kind::Constant: {
    Value held = edge.to.getValue();
    return expand(edge.constant, [&] { return nodeOf(edge.to); }, unrestricted(held.getType()));
  }
  case FlowEdges::Edge::Kind::Dispatch: {
    auto call = cast<CallOpInterface>(edge.call);
    Node callee = nodeOf(FlowPoint::of(cast<Value>(call.getCallableForCallee())));
    unsigned index = static_cast<unsigned>(dispatches.size());
    dispatches.push_back({call, {}});
    classes[find(callee)].dispatches.push_back(index);
    // The labels already there are run now; those that come later, as
    // they come.
    return fire(index, sets[classes[find(callee)].set]);
  }
  }
  llvm_unreachable("every kind of edge is listed");
}

// A flow of a whole value, which the op takes over or reads, moves it out
// of the use that holds it; the flow of a part moves no use's value.
void Graph::flow(Operation *op, const FlowPoint &from, const FlowPoint &to, bool lazy) {
  if (from.kind == FlowPoint::Kind::Operand)
    sink(*from.operand, to);
  else if (from.kind == FlowPoint::Kind::Value)
    for (OpOperand &use : op->getOpOperands())
      if (use.get() == from.value)
        sink(use, to);
  link(nodeOf(from), nodeOf(to), lazy);
}

// A use moves its value into one point: a second edge from it joins its
// target to the first, so the use has one slot to be moved into.
void Graph::sink(OpOperand &use, const FlowPoint &to) {
  auto [it, first] = sinks.try_emplace(&use, to);
  if (!first)
    unify(nodeOf(it->second), nodeOf(to));
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

// A constant part held at the node `at` names, of carrier `carrier`: a
// closure is its label there, its captures at the label's parameters; a
// suspension is that too, and its label returns into the forced state of
// its type; a constructor holds each field at its field's anchor, which is
// its type's wherever the constructor is held, so only a closure needs the
// node of where it is. A shared closure at one point, and a shared
// constructor, is expanded once.
void Graph::expand(Attribute part, function_ref<Node()> at, Type carrier) {
  if (!holdsClosure(part))
    return;
  if (auto closure = dyn_cast<ClosureAttr>(part)) {
    Node node = at();
    if (!expanded.insert({part, node}).second)
      return;
    FlatSymbolRefAttr label = closure.getCallee();
    Label id = labelId(label);
    addLabels(node, id);
    auto fn = table.lookup<FuncOp>(label.getAttr());
    for (auto [i, capture] : llvm::enumerate(closure.getCaptures())) {
      auto index = static_cast<unsigned>(i);
      expand(
          capture, [&] { return nodeOf(FlowPoint::parameter(label, index)); },
          unrestricted(fn.getArgumentTypes()[index]));
    }
    if (isa<LazyType>(carrier))
      unify(nodeOf(FlowPoint::result(label, 0)), nodeOf(FlowAnchor::forcedOf(carrier)));
    return;
  }
  auto con = cast<ConAttr>(part);
  if (!laid.insert(con).second)
    return;
  DataType data = con.getData();
  unsigned tag = con.getTag();
  ArrayRef<Type> fields = data.getCtor(tag).fields;
  eachField(con, [&](Attribute field, unsigned i) {
    expand(
        field, [&] { return nodeOf(FlowAnchor::fieldOf(data, tag, i)); },
        unrestricted(fields[i]));
  });
}

} // namespace idr::labels
