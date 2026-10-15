// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The label solve: a worklist of arrivals and firings over the classes of
// a union-find, each class holding its labels, the nodes its labels flow
// into and the dispatches its labels run. A label that reaches a class is
// one arrival, which gives it to the class's successors and fires it at
// the class's dispatches; a firing adds the label's edges at its call; two
// classes that hold one cell are merged, never coerced. The sets are the
// least solution of the edges, so they do not depend on the walk's or the
// worklist's order.
//
// A pair of a node and a label, or of a dispatch and a label, enters the
// worklist at most once: a label arrives at a class only when it is new to
// the class, and a merge queues each label at the side that lacked it,
// whose node had never held it. There are finitely many nodes, dispatches
// and labels, so the worklist ends with the least solution.

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/STLForwardCompat.h"

#include <algorithm>
#include <cassert>
#include <iterator>

using namespace mlir;

namespace idr {

bool ClosureParts::holds(Attribute part) {
  auto closure = dyn_cast<ClosureAttr>(part);
  auto con = dyn_cast<ConAttr>(part);
  if (!closure && !con)
    return false;
  if (auto it = known.find(part); it != known.end())
    return it->second;
  bool found = static_cast<bool>(closure);
  if (con)
    eachField(con, [&](Attribute field, unsigned) { found = holds(field) || found; });
  known[part] = found;
  return found;
}

} // namespace idr

namespace idr::labels {

namespace {

unsigned at(Node node) { return llvm::to_underlying(node); }
unsigned at(Label label) { return llvm::to_underlying(label); }
unsigned at(Dispatch dispatch) { return llvm::to_underlying(dispatch); }

} // namespace

Graph::Graph(const SymbolTable &table) : out(table) {}

//===----------------------------------------------------------------------===//
// Labels
//===----------------------------------------------------------------------===//

// A label's number, given when it is first met.
Label Graph::labelId(FlatSymbolRefAttr label) {
  auto [it, made] =
      labelIds.try_emplace(label.getAttr(), Label(static_cast<std::uint32_t>(labelNames.size())));
  if (made)
    labelNames.push_back(label);
  return it->second;
}

//===----------------------------------------------------------------------===//
// The union-find and the edges
//===----------------------------------------------------------------------===//

Node Graph::find(Node node) {
  Node root = node;
  while (parents[at(root)] != root)
    root = parents[at(root)];
  while (parents[at(node)] != root) {
    Node next = parents[at(node)];
    parents[at(node)] = root;
    node = next;
  }
  return root;
}

void Graph::link(Node from, Node to, Link how) {
  switch (how) {
  case Link::Include:
    return include(from, to);
  case Link::Unify:
    return unify(from, to);
  }
  llvm_unreachable("every link is listed");
}

// A successor added now is given every label at once, so it is owed
// nothing of what the class gave before.
void Graph::include(Node from, Node to) {
  Node source = find(from);
  if (source == find(to))
    return;
  classes[at(source)].successors.push_back(to);
  for (Label label : classes[at(source)].labels)
    reach(to, label);
}

// One class for both. Each side's successors and dispatches have been
// given, or are owed, the labels of that side; each owes them the labels
// only the other side held, queued as an arrival at the side that lacked
// them, whose node now names the merged class. A successor met twice, or
// one in the merged class itself, is kept once or dropped: it would only
// be given the same labels again.
void Graph::unify(Node a, Node b) {
  Node x = find(a), y = find(b);
  if (x == y)
    return;
  Class &into = classes[at(x)];
  Class &from = classes[at(y)];
  SmallVector<Label> onlyInto, onlyFrom, both;
  std::set_difference(into.labels.begin(), into.labels.end(), from.labels.begin(),
                      from.labels.end(), std::back_inserter(onlyInto));
  std::set_difference(from.labels.begin(), from.labels.end(), into.labels.begin(),
                      into.labels.end(), std::back_inserter(onlyFrom));
  std::set_union(into.labels.begin(), into.labels.end(), from.labels.begin(), from.labels.end(),
                 std::back_inserter(both));
  parents[at(y)] = x;
  into.labels.assign(both.begin(), both.end());
  llvm::append_range(into.successors, from.successors);
  llvm::append_range(into.dispatches, from.dispatches);
  from = Class();
  llvm::SmallDenseSet<Node, 8> roots;
  llvm::erase_if(into.successors, [&](Node next) {
    Node root = find(next);
    return root == x || !roots.insert(root).second;
  });
  for (Label label : onlyFrom) {
    [[maybe_unused]] bool fresh = work.push(Arrival{x, label});
    assert(fresh && "a label new to a class arrives at it once");
  }
  for (Label label : onlyInto) {
    [[maybe_unused]] bool fresh = work.push(Arrival{y, label});
    assert(fresh && "a label new to a class arrives at it once");
  }
}

// `label` reaches `to`'s class, which takes it if it lacks it, and then owes
// it to everything the class gives to.
void Graph::reach(Node to, Label label) {
  Node root = find(to);
  SmallVector<Label, 2> &held = classes[at(root)].labels;
  auto it = llvm::lower_bound(held, label);
  if (it != held.end() && *it == label)
    return;
  held.insert(it, label);
  [[maybe_unused]] bool fresh = work.push(Arrival{root, label});
  assert(fresh && "a label new to a class arrives at it once");
}

//===----------------------------------------------------------------------===//
// The solve
//===----------------------------------------------------------------------===//

// The class the arrival's node names now holds the label; its successors
// take it, and each of its dispatches runs it. Neither changes the class's
// lists: a successor in the class holds the label already.
void Graph::arrive(Arrival arrival) {
  auto [node, label] = arrival;
  const Class &owing = classes[at(find(node))];
  for (Node next : owing.successors)
    reach(next, label);
  for (Dispatch run : owing.dispatches)
    work.push(Firing{run, label});
}

// The label takes the call's arguments after its captures and gives its
// results to the call's.
void Graph::fire(Firing firing) {
  auto [run, label] = firing;
  CallOpInterface call = dispatches[at(run)];
  FlatSymbolRefAttr name = labelNames[at(label)];
  auto fn = out.table.lookup<FuncOp>(name.getAttr());
  Operation::operand_range args = call.getArgOperands();
  assert(fn && fn.getNumArguments() >= args.size() &&
         "a label fits the carrier of the callee that holds it");
  unsigned captures = fn.getNumArguments() - static_cast<unsigned>(args.size());
  auto linkOf = [](Type type) { return isLazyType(type) ? Link::Unify : Link::Include; };
  for (auto [i, arg] : llvm::enumerate(args))
    if (carriesLabels(arg.getType()))
      link(nodeOf(FlowPoint::of(arg)),
           nodeOf(FlowPoint::parameter(name, captures + static_cast<unsigned>(i))),
           linkOf(arg.getType()));
  for (auto [j, result] : llvm::enumerate(call->getResults()))
    if (carriesLabels(result.getType()))
      link(nodeOf(FlowPoint::result(name, static_cast<unsigned>(j))),
           nodeOf(FlowPoint::of(result)), linkOf(result.getType()));
}

// A set's labels in name order. Two equal sets are one attribute: the
// context uniques it.
ArrayAttr Graph::attrOf(ArrayRef<Label> set) const {
  SmallVector<FlatSymbolRefAttr> names;
  for (Label label : set)
    names.push_back(labelNames[at(label)]);
  llvm::sort(names, [](FlatSymbolRefAttr a, FlatSymbolRefAttr b) {
    return a.getValue() < b.getValue();
  });
  return ArrayAttr::get(out.empty.getContext(),
                        SmallVector<Attribute>(names.begin(), names.end()));
}

// Every node's labels are its root's, written once each root's set has its
// attribute.
Solution Graph::solve() && {
  while (std::optional<Work> item = work.pop())
    std::visit(llvm::makeVisitor([&](Arrival arrival) { arrive(arrival); },
                                 [&](Firing firing) { fire(firing); }),
               *item);
  auto n = static_cast<unsigned>(parents.size());
  out.labels.assign(n, out.empty);
  for (unsigned node = 0; node < n; ++node)
    if (parents[node] == Node(node) && !classes[node].labels.empty())
      out.labels[node] = attrOf(classes[node].labels);
  for (unsigned node = 0; node < n; ++node)
    out.labels[node] = out.labels[at(find(Node(node)))];
  return std::move(out);
}

//===----------------------------------------------------------------------===//
// Answers
//===----------------------------------------------------------------------===//

Solution::Solution(const SymbolTable &table)
    : table(table), empty(ArrayAttr::get(table.getOp()->getContext(), {})) {}

ArrayAttr Solution::labelsOf(const FlowPoint &point) const {
  std::optional<Node> node = lookup(point);
  return node ? labels[at(*node)] : empty;
}

ArrayAttr Solution::labelsOf(const FlowAnchor &anchor) const {
  std::optional<Node> node = lookup(anchor);
  return node ? labels[at(*node)] : empty;
}

std::optional<FlowPoint> Solution::sinkOf(OpOperand &operand) const {
  if (auto it = sinks.find(&operand); it != sinks.end())
    return it->second;
  return std::nullopt;
}

} // namespace idr::labels

namespace idr {

namespace {

labels::Solution solveLabels(Operation *program, const SymbolTable &table) {
  labels::Graph graph(table);
  graph.walk(program);
  return std::move(graph).solve();
}

} // namespace

Labels::Labels(Operation *program, AnalysisManager &am)
    : solution(solveLabels(program, am.getAnalysis<SymbolTable>())) {}

ArrayAttr Labels::labelsOf(Value value) const { return solution.labelsOf(FlowPoint::of(value)); }

ArrayAttr Labels::runs(Operation *op) const {
  if (auto apply = dyn_cast<ApplyOp>(op))
    return labelsOf(apply.getCallee());
  if (auto force = dyn_cast<ForceOp>(op))
    return labelsOf(force.getSuspension());
  return solution.none();
}

} // namespace idr
