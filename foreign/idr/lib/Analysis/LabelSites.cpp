// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The graph of the label solve, built by one walk of the program: each op's
// edges as it declares them (flowEdgesOf), those that carry a label kept, a
// node for each point a kept edge names, and the constants' parts expanded
// where they are held. Every point is normalized to its key (keyOf) before
// it is given a node: a function's parameter is its entry block's
// argument, one node; a part of a value is its anchor's node.

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/STLForwardCompat.h"

using namespace mlir;

namespace idr::labels {

namespace {

unsigned at(Node node) { return llvm::to_underlying(node); }

// The value a parameter of a function is: its entry block's argument.
Value parameterValue(const SymbolTable &table, FlatSymbolRefAttr function, unsigned index) {
  auto fn = table.lookup<FuncOp>(function.getAttr());
  assert(fn && "a label is a function of the program");
  return fn.getArgument(index);
}

} // namespace

Node Graph::fresh() {
  Node node = Node(static_cast<unsigned>(parents.size()));
  parents.push_back(node);
  classes.emplace_back();
  return node;
}

PointKey Solution::keyOf(const FlowPoint &point) const {
  return std::visit(
      llvm::makeVisitor(
          [](FlowPoint::Taken taken) -> PointKey { return taken.use->get(); },
          [](FlowPoint::Whole whole) -> PointKey { return whole.value; },
          [](const FlowPoint::Part &part) -> PointKey { return part.anchor; },
          [&](FlowPoint::Parameter param) -> PointKey {
            return parameterValue(table, param.function, param.index);
          },
          [](FlowPoint::Result result) -> PointKey {
            return ResultKey{result.function.getAttr(), result.index};
          }),
      point.at);
}

std::optional<Node> Solution::lookup(const PointKey &key) const {
  if (auto it = nodes.find(key); it != nodes.end())
    return it->second;
  return std::nullopt;
}

Node Graph::nodeOf(const PointKey &key) {
  auto [it, made] = out.nodes.try_emplace(key, Node());
  if (made)
    it->second = fresh();
  return it->second;
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
  std::visit(
      llvm::makeVisitor(
          [&](const FlowEdges::Flow &move) {
            if (!edge.carriesAny(Carriers::labels()))
              return;
            flow(op, move.from, move.to, linkOf(edge.carriers));
          },
          [&](const FlowEdges::Unify &move) {
            unify(nodeOf(out.keyOf(move.a)), nodeOf(out.keyOf(move.b)));
          },
          [&](const FlowEdges::Source &move) { reach(nodeOf(move.to), labelId(move.label)); },
          [](const FlowEdges::Fresh &) {},
          [](const FlowEdges::Release &) {},
          [&](const FlowEdges::Constant &move) {
            expand(move.part, [&] { return nodeOf(move.to); }, unrestricted(move.to.getType()));
          },
          [&](FlowEdges::Dispatch move) {
            CallOpInterface call = move.call;
            Node callee = find(nodeOf(cast<Value>(call.getCallableForCallee())));
            auto run = Dispatch(static_cast<unsigned>(dispatches.size()));
            dispatches.push_back(call);
            classes[at(callee)].dispatches.push_back(run);
            // The labels already there are owed now; those that come later,
            // as they arrive.
            for (Label label : classes[at(callee)].labels)
              work.push(Firing{run, label});
          }),
      edge.move);
}

// A flow of a whole value, which the op takes over or reads, moves it out
// of the use that holds it; the flow of a part moves no use's value, and a
// parameter or a result is no use's.
void Graph::flow(Operation *op, const FlowPoint &from, const FlowPoint &to, Link how) {
  std::visit(llvm::makeVisitor([&](FlowPoint::Taken taken) { sink(*taken.use, to); },
                               [&](FlowPoint::Whole whole) {
                                 for (OpOperand &use : op->getOpOperands())
                                   if (use.get() == whole.value)
                                     sink(use, to);
                               },
                               [](const FlowPoint::Part &) {}, [](FlowPoint::Parameter) {},
                               [](FlowPoint::Result) {}),
             from.at);
  link(nodeOf(out.keyOf(from)), nodeOf(out.keyOf(to)), how);
}

// A use moves its value into one point: a second edge from it joins its
// target to the first, so the use has one slot to be moved into.
void Graph::sink(OpOperand &use, const FlowPoint &to) {
  auto [it, first] = out.sinks.try_emplace(&use, to);
  if (!first)
    unify(nodeOf(out.keyOf(it->second)), nodeOf(out.keyOf(to)));
}

// A constant part held at the node `at` names, of carrier `carrier`: a
// closure is its label there, its captures at the label's parameters; a
// suspension is that too, and its label returns into the forced state of
// its type; a constructor holds each field at its field's anchor, which is
// its type's wherever the constructor is held, so only a closure needs the
// node of where it is. A shared closure at one point, and a shared
// constructor, is expanded once.
void Graph::expand(Attribute part, function_ref<Node()> at, Type carrier) {
  if (!holding.holds(part))
    return;
  if (auto closure = dyn_cast<ClosureAttr>(part)) {
    Node node = at();
    if (!expanded.insert({part, node}).second)
      return;
    FlatSymbolRefAttr label = closure.getCallee();
    reach(node, labelId(label));
    auto fn = out.table.lookup<FuncOp>(label.getAttr());
    for (auto [i, capture] : llvm::enumerate(closure.getCaptures())) {
      auto index = static_cast<unsigned>(i);
      expand(
          capture, [&] { return nodeOf(out.keyOf(FlowPoint::parameter(label, index))); },
          unrestricted(fn.getArgumentTypes()[index]));
    }
    if (auto lazy = dyn_cast<LazyType>(carrier))
      unify(nodeOf(out.keyOf(FlowPoint::result(label, 0))), nodeOf(FlowAnchor::forcedOf(lazy)));
    return;
  }
  auto con = cast<ConAttr>(part);
  if (!laid.insert(con).second)
    return;
  DataType data = con.getData();
  Tag tag = con.getTag();
  ArrayRef<Type> fields = data.getCtor(tag).fields;
  con.walkFields([&](Attribute field, unsigned i) {
    expand(
        field, [&] { return nodeOf(FlowAnchor::fieldOf(data, tag, i)); },
        unrestricted(fields[i]));
  });
}

} // namespace idr::labels
