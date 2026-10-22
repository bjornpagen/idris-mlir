// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The reading of the program as statements about points, and the graph the
// solve builds from them. One walk of the program reads each op's edges as
// it declares them (flowEdgesOf), keeps those that carry a label, and
// expands the constants' parts where they are held. Every point is
// normalized to its key (keyOf) before it is stated: a function's parameter
// is its entry block's argument, one key; a part of a value is its
// anchor's key. A call in tail position, direct by its own fact or a
// dispatch by the one definition of tail position, states its callee's
// result points one set with its caller's. A constant is looked into on an
// explicit stack, so one of any depth takes no recursion; so is the
// question of which of its parts hold a closure, which defunctionalization
// asks too.

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Tail.h"

#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

#include <utility>
#include <variant>

using namespace mlir;

namespace idr {

namespace {

// Where a constructor stands on a walk of a constant: met, its fields not
// yet pushed; or opened, its fields done before it is popped again.
enum class Visit : std::uint8_t { Met, Opened };

} // namespace

bool ClosureParts::answer(Attribute part) const {
  if (!isa<ClosureAttr>(part) && !isa<ConAttr>(part))
    return false;
  return known.find(part)->second;
}

bool ClosureParts::holds(Attribute part) {
  footprint::Vector<std::pair<Attribute, Visit>> work{{part, Visit::Met}};
  while (!work.empty()) {
    auto [at, visit] = work.back();
    auto con = dyn_cast<ConAttr>(at);
    if ((!con && !isa<ClosureAttr>(at)) || known.contains(at)) {
      work.pop_back();
      continue;
    }
    if (!con) {
      known[at] = true;
      work.pop_back();
      continue;
    }
    if (visit == Visit::Met) {
      work.back().second = Visit::Opened;
      con.walkFields([&](Attribute field, unsigned) { work.push_back({field, Visit::Met}); });
      continue;
    }
    bool found = false;
    con.walkFields([&](Attribute field, unsigned) { found = found || answer(field); });
    known[at] = found;
    work.pop_back();
  }
  return answer(part);
}

} // namespace idr

namespace idr::labels {

namespace {

// The value a parameter of a function is: its entry block's argument. A
// label is a function of the program, which the verifier proved.
Value parameterValue(const SymbolTable &table, FlatSymbolRefAttr function, unsigned index) {
  return table.lookup<FuncOp>(function.getAttr()).getArgument(index);
}

// `call` gives its caller's results, being in tail position: each result
// point of `callee` that carries a label is one set with its caller's.
void tailResults(const SymbolTable &table, FlatSymbolRefAttr callee, Operation *call,
                 Statements &to) {
  auto caller = FlatSymbolRefAttr::get(call->getParentOfType<FuncOp>().getSymNameAttr());
  for (auto [j, result] : llvm::enumerate(call->getResults()))
    if (carriesLabels(result.getType())) {
      auto index = static_cast<unsigned>(j);
      to.links.push_back({keyOf(table, FlowPoint::result(callee, index)),
                          keyOf(table, FlowPoint::result(caller, index)), Link::Unify});
    }
}

// A constant part to expand at a point, of a carrier; or the link a
// suspension's label owes once its captures are expanded.
struct Expansion {
  Attribute part;
  PointKey at;
  Type carrier;
};
using Pending = std::variant<Expansion, Statements::Linked>;

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
  void expandOne(const Expansion &next, footprint::Vector<Pending> &work);

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
            to.links.push_back({keyOf(table, move.a), keyOf(table, move.b), Link::Unify});
          },
          [&](const FlowEdges::Source &move) { to.sources.push_back({move.to, move.label}); },
          [](const FlowEdges::Fresh &) {},
          [](const FlowEdges::Release &) {},
          [](const FlowEdges::Overwrite &) {},
          [&](const FlowEdges::Constant &move) {
            expand(move.part, move.to, unrestricted(move.to.getType()));
          },
          [&](FlowEdges::Dispatch move) {
            CallOpInterface call = move.call;
            Standing standing =
                tail::inTailPosition(call.getOperation()) ? Standing::Tail : Standing::Within;
            to.dispatches.push_back({cast<Value>(call.getCallableForCallee()), call, standing});
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
  to.links.push_back({keyOf(table, from), keyOf(table, target), how});
}

// A use moves its value into one point: a second edge from it joins its
// target to the first, so the use has one slot to be moved into.
void Reading::sink(OpOperand &use, const FlowPoint &target) {
  auto [it, first] = sinks.try_emplace(&use, target);
  if (!first)
    to.links.push_back({keyOf(table, it->second), keyOf(table, target), Link::Unify});
}

// A constant part held at the point `at`, of carrier `carrier`: a closure
// is its label there, its captures at the label's parameters; a suspension
// is that too, and its label returns into the forced state of its type; a
// constructor holds each field at its field's anchor, which is its type's
// wherever the constructor is held, so only a closure needs the point
// where it is. A shared closure at one point, and a shared constructor, is
// expanded once. The parts are expanded in the order a walk of the
// constant meets them, each part's statements before its parts'.
void Reading::expand(Attribute part, const PointKey &at, Type carrier) {
  footprint::Vector<Pending> work;
  work.push_back(Expansion{part, at, carrier});
  while (!work.empty()) {
    Pending next = std::move(work.back());
    work.pop_back();
    std::visit(llvm::makeVisitor(
                   [&](const Expansion &expansion) { expandOne(expansion, work); },
                   [&](const Statements::Linked &linked) { to.links.push_back(linked); }),
               next);
  }
}

// One part's statements, its own parts pushed to come next, the first on
// top, and a suspension's link beneath them, after its captures.
void Reading::expandOne(const Expansion &next, footprint::Vector<Pending> &work) {
  if (!holding.holds(next.part))
    return;
  if (auto closure = dyn_cast<ClosureAttr>(next.part)) {
    if (!expanded.insert({next.part, next.at}).second)
      return;
    FlatSymbolRefAttr label = closure.getCallee();
    to.sources.push_back({next.at, label});
    if (auto lazy = dyn_cast<LazyType>(next.carrier))
      work.push_back(Statements::Linked{keyOf(table, FlowPoint::result(label, 0)),
                                        FlowAnchor::forcedOf(lazy), Link::Unify});
    auto fn = table.lookup<FuncOp>(label.getAttr());
    ArrayAttr captures = closure.getCaptures();
    for (auto index = static_cast<unsigned>(captures.size()); index-- > 0;)
      work.push_back(Expansion{captures[index],
                               keyOf(table, FlowPoint::parameter(label, index)),
                               unrestricted(fn.getArgumentTypes()[index])});
    return;
  }
  auto con = cast<ConAttr>(next.part);
  if (!laid.insert(con).second)
    return;
  DataType data = con.getData();
  Tag tag = con.getTag();
  ArrayRef<Type> fields = data.ctor(tag).fields;
  footprint::Vector<Expansion> parts;
  con.walkFields([&](Attribute field, unsigned i) {
    parts.push_back({field, FlowAnchor::fieldOf(data, tag, i), unrestricted(fields[i])});
  });
  for (Expansion &part : llvm::reverse(parts))
    work.push_back(std::move(part));
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
    if (auto call = dyn_cast<CallOp>(op); call && call.getTailKind() == TailKind::tail)
      tailResults(table, call.getCalleeAttr(), op, to);
  });
}

// The label takes the call's arguments after its captures and gives its
// results to the call's, and its caller's where the call is in tail
// position. A label fits the carrier of the callee that holds it, which
// the flow rule proved: it has every argument as a parameter.
void readFiring(const SymbolTable &table, CallOpInterface call, Standing standing,
                FlatSymbolRefAttr label, Statements &to) {
  auto fn = table.lookup<FuncOp>(label.getAttr());
  Operation::operand_range args = call.getArgOperands();
  unsigned captures = fn.getNumArguments() - static_cast<unsigned>(args.size());
  for (auto [i, arg] : llvm::enumerate(args))
    if (carriesLabels(arg.getType()))
      to.links.push_back(
          {arg, keyOf(table, FlowPoint::parameter(label, captures + static_cast<unsigned>(i))),
           linkOf(Carriers::of(arg.getType()))});
  for (auto [j, result] : llvm::enumerate(call->getResults()))
    if (carriesLabels(result.getType()))
      to.links.push_back({keyOf(table, FlowPoint::result(label, static_cast<unsigned>(j))),
                          Value(result), linkOf(Carriers::of(result.getType()))});
  if (standing == Standing::Tail)
    tailResults(table, label, call.getOperation(), to);
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

void Graph::take(const Statements &statements) {
  for (const Statements::Source &source : statements.sources)
    sources.emplace_back(nodeOf(source.at), out.labelOf(source.label));
  for (const Statements::Linked &linked : statements.links)
    link(nodeOf(linked.from), nodeOf(linked.to), linked.how);
  for (const Statements::Dispatched &dispatched : statements.dispatches)
    runs.push_back(Run{dispatched.call, dispatched.standing, nodeOf(dispatched.callee), SetId{}});
}

// Every function of the program is a label, by its position: the labels'
// one order, minted before any statement names one.
void Graph::walk(Operation *program) {
  for (FuncOp fn : cast<ProgramOp>(program).getOps<FuncOp>()) {
    out.ranks.try_emplace(fn.getSymNameAttr(), Label(static_cast<std::uint32_t>(out.symbols.size())));
    out.symbols.push_back(FlatSymbolRefAttr::get(fn.getSymNameAttr()));
  }
  Statements statements;
  readProgram(program, out.table, statements, out.sinks);
  take(statements);
}

} // namespace idr::labels
