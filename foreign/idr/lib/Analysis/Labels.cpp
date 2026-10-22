// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The label solve, in waves over the classes of a union-find. A class holds
// the id of its set, interned in the solve's table, and the nodes whose
// classes include it; a dispatch holds the labels it has run. A wave takes
// the classes downstream of a new edge, collapses each cycle of inclusions
// among them into one class, since a cycle's sets are equal in every
// solution (two points that hold one cell are a cycle of two), and
// computes each class's set once, after every class it includes: one
// union of its members' sets and of what its inputs owe it. A class with one distinct input set takes
// that set's id and reads no label. Then each dispatch runs the labels its
// callee holds that it has not run, each adding the label's edges, which
// the next wave owes. The sets only grow, a wave gives each class it takes
// the least set that holds the edges present, and a firing adds exactly
// the edges of a label that has reached its call, so the waves end with
// the least solution of the statements, whatever the order of the walk.
//
// The waves end: a wave after the first exists only because the one before
// ran a label new to a dispatch, and a dispatch's labels only grow, within
// the program's finitely many. A wave is a loop over the classes it takes
// and their edges. Every point is numbered before the first wave, so a
// wave and a firing read numbers alone, and every table here is indexed
// by one.

#include "idr/Analysis/Labels.h"

#include "idr/Analysis/Solver/Components.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/LabelGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "mlir/IR/BuiltinAttributes.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/STLForwardCompat.h"

#include <algorithm>
#include <iterator>
#include <ranges>
#include <utility>

using namespace mlir;

namespace idr::labels {

namespace {

unsigned at(Node node) { return llvm::to_underlying(node); }

} // namespace

//===----------------------------------------------------------------------===//
// The union-find and the edges
//===----------------------------------------------------------------------===//

// Every point is a node of its own class before any edge.
Graph::Graph(Read reading, MLIRContext *context) : read(std::move(reading)), context(context) {
  std::uint32_t n = read.points.size();
  parents.reserve(n);
  for (std::uint32_t node = 0; node < n; ++node)
    parents.push_back(Node(node));
  classes.resize(n);
  take(read.statements);
  read.statements = Statements();
  for (const Dispatched &dispatched : read.dispatches)
    runs.push_back(Run{dispatched.callee, SetId{}});
}

void Graph::take(const Statements &statements) {
  for (const Statements::Source &source : statements.sources)
    sources.emplace_back(source.at, source.label);
  for (const Statements::Linked &linked : statements.links)
    link(linked.from, linked.to, linked.how);
}

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

Link linkOf(Carriers carriers) {
  return carriers.contains(Carrier::Suspension) ? Link::Unify : Link::Include;
}

// Two points that hold one set include each other: a cycle, which the
// next wave collapses into one class like any other.
void Graph::link(Node from, Node to, Link how) {
  include(from, to);
  if (how == Link::Unify)
    include(to, from);
}

// An edge added now owes its target its source's set at the next wave.
void Graph::include(Node from, Node to) {
  Node source = find(from);
  if (source == find(to))
    return;
  classes[at(source)].successors.push_back(to);
  added.emplace_back(from, to);
  dirty.push_back(to);
}

// The classes of the roots `x` and `y` as one, under the root whose list of
// successors is the longer, so that no long list is copied twice; the
// merged class's root. Its set is the wave's to compute, from both.
Node Graph::merge(Node x, Node y) {
  if (classes[at(x)].successors.size() < classes[at(y)].successors.size())
    std::swap(x, y);
  parents[at(y)] = x;
  Class from = std::exchange(classes[at(y)], Class());
  llvm::append_range(classes[at(x)].successors, from.successors);
  return x;
}

//===----------------------------------------------------------------------===//
// The solve
//===----------------------------------------------------------------------===//

// Each class holds the labels that start at its points.
void Graph::seed() {
  footprint::Vector<std::pair<Node, Label>> starts;
  for (const auto &[node, label] : sources)
    starts.emplace_back(find(node), label);
  sources = {};
  llvm::sort(starts);
  starts.erase(std::unique(starts.begin(), starts.end()), starts.end());
  for (auto first = starts.begin(); first != starts.end();) {
    Node root = first->first;
    auto last = std::find_if(first, starts.end(), [&](const auto &start) { return start.first != root; });
    footprint::Vector<Label> own;
    for (auto it = first; it != last; ++it)
      own.push_back(it->second);
    footprint::Vector<SetId> both = {classes[at(root)].labels, sets.intern(own)};
    classes[at(root)].labels = sets.unite(both);
    first = last;
  }
}

// One wave: the classes downstream of a node the last wave left owed, its
// cycles collapsed, each set computed after the sets it includes; then
// the firings the dispatches owe.
footprint::Vector<Firing> Graph::wave() {
  // The classes the wave takes, as roots, each once: those owed, and every
  // class that includes one taken. A class is taken in this wave when its
  // stamp is this wave's.
  ++waves;
  takenIn.resize(parents.size(), 0);
  vertexIn.resize(parents.size(), 0);
  footprint::Vector<Node> order;
  auto take = [&](Node node) {
    ++steps;
    Node root = find(node);
    if (takenIn[at(root)] == waves)
      return;
    takenIn[at(root)] = waves;
    vertexIn[at(root)] = static_cast<unsigned>(order.size());
    order.push_back(root);
  };
  auto vertexOf = [&](Node node) { return vertexIn[at(find(node))]; };
  for (Node node : dirty)
    take(node);
  dirty.clear();
  for (size_t v = 0; v < order.size(); ++v)
    for (Node next : classes[at(order[v])].successors)
      take(next);

  // Each class's successors as the wave's roots, each once, itself never:
  // the wave's graph of inclusions over its vertices, whose rows are each
  // class's included classes in the order met.
  auto n = static_cast<unsigned>(order.size());
  Count<WaveVertex> vertices(n);
  auto vertex = [](unsigned v) { return WaveVertex(v); };
  CsrBuilder<WaveVertexTag> inclusions(vertices);
  footprint::Vector<unsigned> seen(n, n);
  for (unsigned v = 0; v < n; ++v) {
    footprint::Vector<Node> kept;
    for (Node next : classes[at(order[v])].successors) {
      ++steps;
      unsigned w = vertexOf(next);
      if (w == v || seen[w] == v)
        continue;
      seen[w] = v;
      inclusions.edge(vertex(v), vertex(w));
      kept.push_back(order[w]);
    }
    classes[at(order[v])].successors = std::move(kept);
  }

  // What each class is owed besides the sets it held: the sets of the
  // edges added since the last wave, and of the classes it includes whose
  // sets grow in this one.
  footprint::Vector<footprint::Vector<SetId>> owed(n);
  for (auto [from, to] : added)
    owed[vertexOf(to)].push_back(classes[at(find(from))].labels);
  steps += added.size();
  added.clear();
  footprint::Vector<SetId> before(n);
  for (unsigned v = 0; v < n; ++v)
    before[v] = classes[at(order[v])].labels;

  // The components come bottom-up, so the last includes no other class of
  // the wave; each is one class once its members merge, its set computed
  // after the sets of the components whose classes it includes. A member
  // whose set did not grow owes its successors nothing new.
  Csr<WaveVertexTag> graph = std::move(inclusions).finish();
  Partition<WaveVertexTag> parts = components(graph);
  for (auto c : std::views::reverse(parts.size().ids())) {
    IdRange<WaveVertex> part = parts.members(c);
    footprint::Vector<SetId> inputs;
    for (WaveVertex v : part) {
      inputs.push_back(before[v.index()]);
      llvm::append_range(inputs, owed[v.index()]);
    }
    Node root = order[part.front().index()];
    for (auto member = part.begin() + 1; member != part.end(); ++member)
      root = merge(root, order[(*member).index()]);
    SetId set = sets.unite(inputs);
    classes[at(root)].labels = set;
    for (WaveVertex v : part)
      if (set != before[v.index()])
        for (WaveVertex w : graph.successors(v))
          if (parts.componentOf(w) != c)
            owed[w.index()].push_back(set);
  }

  // Each dispatch runs the labels its callee holds that it has not run: it
  // has run a subset of them.
  footprint::Vector<Firing> firings;
  for (auto [d, run] : llvm::enumerate(runs)) {
    ++steps;
    SetId set = classes[at(find(run.callee))].labels;
    if (set == run.ran)
      continue;
    footprint::Vector<Label> unrun;
    ArrayRef<Label> now = sets.members(set), had = sets.members(run.ran);
    steps += now.size() + had.size();
    std::set_difference(now.begin(), now.end(), had.begin(), had.end(), std::back_inserter(unrun));
    for (Label label : unrun)
      firings.emplace_back(Dispatch(static_cast<unsigned>(d)), label);
    run.ran = set;
  }
  return firings;
}

// The label's edges at the dispatch's call, which the next wave owes.
void Graph::fire(Firing firing) {
  auto [run, label] = firing;
  Statements owed;
  readFiring(read, run, label, owed);
  take(owed);
}

// Every node's labels are its root's, one attribute per set: its labels
// in the labels' order, their functions' order in the program.
Solution Graph::solve(solver::Work &work) && {
  seed();
  for (footprint::Vector<Firing> firings = wave(); !firings.empty(); firings = wave())
    for (Firing firing : firings)
      fire(firing);
  work.add(steps + sets.labelsRead());
  // Each set's attribute, made the first time a node holds the set.
  ArrayAttr empty = ArrayAttr::get(context, {});
  footprint::Vector<ArrayAttr> attrs(sets.size());
  auto n = static_cast<unsigned>(parents.size());
  footprint::Vector<ArrayAttr> labels(n, empty);
  for (unsigned node = 0; node < n; ++node) {
    SetId set = classes[at(find(Node(node)))].labels;
    if (set == SetId{})
      continue;
    ArrayAttr &attr = attrs[llvm::to_underlying(set)];
    if (!attr) {
      footprint::Vector<Attribute> members;
      for (Label label : sets.members(set))
        members.push_back(read.points.symbolOf(label));
      attr = ArrayAttr::get(context, members);
    }
    labels[node] = attr;
  }
  return Solution(std::move(read.points), std::move(read.sinks), std::move(labels), empty);
}

//===----------------------------------------------------------------------===//
// Answers
//===----------------------------------------------------------------------===//

Solution::Solution(Points points, Sinks sinks, footprint::Vector<ArrayAttr> labels, ArrayAttr empty)
    : points(std::move(points)), sinks(std::move(sinks)), labels(std::move(labels)), empty(empty) {}

// A point is found where the reading named it, and never made here.
ArrayAttr Solution::labelsOf(const FlowSource &point) const {
  return labelsAt(nodeOf(points, point, [&](const auto &key) { return points.find(key); }));
}

ArrayAttr Solution::labelsOf(const PointKey &key) const {
  auto ofResult = [&](FlowSource::Result result) {
    return labelsAt(points.result(points.labelOf(result.function), result.index));
  };
  return match(
      key, [&](Value value) { return labelsOf(value); },
      [&](const FlowAnchor &anchor) { return labelsOf(anchor); }, ofResult);
}

// Both sets hold their labels in one order, so `a`'s labels are met along
// `b` in their own order, each after the one before.
bool within(ArrayAttr a, ArrayAttr b) {
  if (a == b)
    return true;
  ArrayRef<Attribute> along = b.getValue();
  const Attribute *at = along.begin();
  for (Attribute label : a) {
    at = std::find(at, along.end(), label);
    if (at == along.end())
      return false;
    ++at;
  }
  return true;
}

std::optional<unsigned> Solution::positionIn(ArrayAttr set, FlatSymbolRefAttr label) const {
  Label wanted = points.labelOf(label);
  ArrayRef<Attribute> members = set.getValue();
  const Attribute *it = llvm::partition_point(members, [&](Attribute member) {
    return points.labelOf(cast<FlatSymbolRefAttr>(member)) < wanted;
  });
  if (it == members.end() || *it != label)
    return std::nullopt;
  return static_cast<unsigned>(it - members.begin());
}

} // namespace idr::labels

namespace idr {

Labels::Labels(Operation *program, AnalysisManager &am) : solution([&] {
  labels::Graph graph(labels::readProgram(program, std::get<0>(reads(am))), program->getContext());
  return std::move(graph).solve(spent);
}()) {}

} // namespace idr
