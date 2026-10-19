// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The reading of the program as statements about points, and the graph the
// solve builds from them. One walk of the program reads each op's edges as
// it declares them (flowEdgesOf), keeps those that carry a label, and
// expands the constants' parts where they are held. Every point is
// normalized to its key (keyOf) before it is stated: a function's parameter
// is its entry block's argument, one key; a part of a value is its
// anchor's key.

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::labels {

namespace {

// The value a parameter of a function is: its entry block's argument.
Value parameterValue(const SymbolTable &table, FlatSymbolRefAttr function, unsigned index) {
  auto fn = table.lookup<FuncOp>(function.getAttr());
  assert(fn && "a label is a function of the program");
  return fn.getArgument(index);
}

// One reading of a program: the sinks it gives, and the constants it has
// expanded, each once.
class Reading {
public:
  Reading(const SymbolTable &table, Statements &to, llvm::DenseMap<OpOperand *, FlowPoint> &sinks)
      : table(table), to(to), sinks(sinks) {}

  void add(Operation *op, const FlowEdges::Edge &edge);

private:
  void flow(Operation *op, const FlowPoint &from, const FlowPoint &target, Link how);
  void sink(OpOperand &use, const FlowPoint &target);
  void expand(Attribute part, const PointKey &at, Type carrier);

  const SymbolTable &table;
  Statements &to;
  llvm::DenseMap<OpOperand *, FlowPoint> &sinks;
  // The closure constants already expanded at a point, and the constructor
  // constants already laid out at their anchors.
  llvm::DenseSet<std::pair<Attribute, PointKey>> expanded;
  llvm::DenseSet<Attribute> laid;
  ClosureParts holding;
};

// A flow that carries no label, and what only a reference does (a fresh
// cell, a reference given up), states nothing. A source, a unification and
// a dispatch are of labels alone. A constant is looked into whatever
// carrier holds it: a constructor of any data type may hold a closure in a
// field.
void Reading::add(Operation *op, const FlowEdges::Edge &edge) {
  std::visit(
      llvm::makeVisitor(
          [&](const FlowEdges::Flow &move) {
            if (!edge.carriesAny(Carriers::labels()))
              return;
            flow(op, move.from, move.to, linkOf(edge.carriers));
          },
          [&](const FlowEdges::Unify &move) {
            to.link(keyOf(table, move.a), keyOf(table, move.b), Link::Unify);
          },
          [&](const FlowEdges::Source &move) { to.source(move.to, move.label); },
          [](const FlowEdges::Fresh &) {},
          [](const FlowEdges::Release &) {},
          [](const FlowEdges::Overwrite &) {},
          [&](const FlowEdges::Constant &move) {
            expand(move.part, move.to, unrestricted(move.to.getType()));
          },
          [&](FlowEdges::Dispatch move) {
            CallOpInterface call = move.call;
            to.dispatch(cast<Value>(call.getCallableForCallee()), call);
          }),
      edge.move);
}

// A flow of a whole value, which the op takes over or reads, moves it out
// of the use that holds it; the flow of a part moves no use's value, and a
// parameter or a result is no use's.
void Reading::flow(Operation *op, const FlowPoint &from, const FlowPoint &target, Link how) {
  std::visit(llvm::makeVisitor([&](FlowPoint::Taken taken) { sink(*taken.use, target); },
                               [&](FlowPoint::Whole whole) {
                                 for (OpOperand &use : op->getOpOperands())
                                   if (use.get() == whole.value)
                                     sink(use, target);
                               },
                               [](const FlowPoint::Part &) {}, [](FlowPoint::Parameter) {},
                               [](FlowPoint::Result) {}),
             from.at);
  to.link(keyOf(table, from), keyOf(table, target), how);
}

// A use moves its value into one point: a second edge from it joins its
// target to the first, so the use has one slot to be moved into.
void Reading::sink(OpOperand &use, const FlowPoint &target) {
  auto [it, first] = sinks.try_emplace(&use, target);
  if (!first)
    to.link(keyOf(table, it->second), keyOf(table, target), Link::Unify);
}

// A constant part held at the point `at`, of carrier `carrier`: a closure
// is its label there, its captures at the label's parameters; a suspension
// is that too, and its label returns into the forced state of its type; a
// constructor holds each field at its field's anchor, which is its type's
// wherever the constructor is held, so only a closure needs the point
// where it is. A shared closure at one point, and a shared constructor, is
// expanded once.
void Reading::expand(Attribute part, const PointKey &at, Type carrier) {
  if (!holding.holds(part))
    return;
  if (auto closure = dyn_cast<ClosureAttr>(part)) {
    if (!expanded.insert({part, at}).second)
      return;
    FlatSymbolRefAttr label = closure.getCallee();
    to.source(at, label);
    auto fn = table.lookup<FuncOp>(label.getAttr());
    for (auto [i, capture] : llvm::enumerate(closure.getCaptures())) {
      auto index = static_cast<unsigned>(i);
      expand(capture, keyOf(table, FlowPoint::parameter(label, index)),
             unrestricted(fn.getArgumentTypes()[index]));
    }
    if (auto lazy = dyn_cast<LazyType>(carrier))
      to.link(keyOf(table, FlowPoint::result(label, 0)), FlowAnchor::forcedOf(lazy), Link::Unify);
    return;
  }
  auto con = cast<ConAttr>(part);
  if (!laid.insert(con).second)
    return;
  DataType data = con.getData();
  Tag tag = con.getTag();
  ArrayRef<Type> fields = data.getCtor(tag).fields;
  con.walkFields([&](Attribute field, unsigned i) {
    expand(field, FlowAnchor::fieldOf(data, tag, i), unrestricted(fields[i]));
  });
}

} // namespace

PointKey keyOf(const SymbolTable &table, const FlowPoint &point) {
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

void readProgram(Operation *program, const SymbolTable &table, Statements &to,
                 llvm::DenseMap<OpOperand *, FlowPoint> &sinks) {
  Reading reading(table, to, sinks);
  FlowEdges edges;
  program->walk([&](Operation *op) {
    flowEdgesOf(op, edges);
    for (const FlowEdges::Edge &edge : edges.edges())
      reading.add(op, edge);
    edges.clear();
  });
}

// The label takes the call's arguments after its captures and gives its
// results to the call's.
void readFiring(const SymbolTable &table, CallOpInterface call, FlatSymbolRefAttr label,
                Statements &to) {
  auto fn = table.lookup<FuncOp>(label.getAttr());
  Operation::operand_range args = call.getArgOperands();
  assert(fn && fn.getNumArguments() >= args.size() &&
         "a label fits the carrier of the callee that holds it");
  unsigned captures = fn.getNumArguments() - static_cast<unsigned>(args.size());
  for (auto [i, arg] : llvm::enumerate(args))
    if (carriesLabels(arg.getType()))
      to.link(arg, keyOf(table, FlowPoint::parameter(label, captures + static_cast<unsigned>(i))),
              linkOf(Carriers::of(arg.getType())));
  for (auto [j, result] : llvm::enumerate(call->getResults()))
    if (carriesLabels(result.getType()))
      to.link(keyOf(table, FlowPoint::result(label, static_cast<unsigned>(j))), Value(result),
              linkOf(Carriers::of(result.getType())));
}

//===----------------------------------------------------------------------===//
// The graph
//===----------------------------------------------------------------------===//

Node Graph::fresh() {
  Node node = Node(static_cast<unsigned>(parents.size()));
  parents.push_back(node);
  classes.emplace_back();
  return node;
}

Node Graph::nodeOf(const PointKey &key) {
  auto [it, made] = out.nodes.try_emplace(key, Node());
  if (made)
    it->second = fresh();
  return it->second;
}

void Graph::Builder::source(const PointKey &at, FlatSymbolRefAttr label) {
  graph.sources.emplace_back(graph.nodeOf(at), label);
}

void Graph::Builder::link(const PointKey &from, const PointKey &to, Link how) {
  graph.link(graph.nodeOf(from), graph.nodeOf(to), how);
}

void Graph::Builder::dispatch(const PointKey &callee, CallOpInterface call) {
  graph.runs.push_back(Run{call, graph.nodeOf(callee), SetId{}});
}

void Graph::walk(Operation *program) {
  Builder builder(*this);
  readProgram(program, out.table, builder, out.sinks);
}

} // namespace idr::labels
