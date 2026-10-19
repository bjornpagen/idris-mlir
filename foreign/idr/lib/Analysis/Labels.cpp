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
// and their edges.

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Scc.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/STLForwardCompat.h"

#include <algorithm>
#include <cassert>
#include <iterator>
#include <utility>

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
    con.walkFields([&](Attribute field, unsigned) { found = holds(field) || found; });
  known[part] = found;
  return found;
}

} // namespace idr

namespace idr::labels {

namespace {

unsigned at(Node node) { return llvm::to_underlying(node); }
unsigned at(Label label) { return llvm::to_underlying(label); }
unsigned at(Dispatch dispatch) { return llvm::to_underlying(dispatch); }

bool byName(Attribute a, Attribute b) {
  return cast<FlatSymbolRefAttr>(a).getValue() < cast<FlatSymbolRefAttr>(b).getValue();
}

} // namespace

//===----------------------------------------------------------------------===//
// Sets
//===----------------------------------------------------------------------===//

// The empty set is id 0, and is never looked up by its members.
SetTable::SetTable() { sets.emplace_back(); }

SetId SetTable::intern(ArrayRef<Label> members) {
  if (members.empty())
    return SetId{};
  if (auto it = ids.find(members); it != ids.end())
    return it->second;
  ArrayRef<Label> kept = members.copy(storage);
  auto id = SetId(static_cast<std::uint32_t>(sets.size()));
  sets.push_back(kept);
  ids.try_emplace(kept, id);
  return id;
}

ArrayRef<Label> SetTable::members(SetId set) const { return sets[llvm::to_underlying(set)]; }

bool SetTable::within(SetId part, SetId whole) const {
  ArrayRef<Label> in = members(whole);
  return llvm::all_of(members(part), [&](Label label) { return std::binary_search(in.begin(), in.end(), label); });
}

// The union of two or more distinct sets is the largest of them when it
// holds the others, and is made once per tuple of ids.
SetId SetTable::unite(SmallVectorImpl<SetId> &inputs) {
  llvm::erase(inputs, SetId{});
  llvm::sort(inputs);
  inputs.erase(std::unique(inputs.begin(), inputs.end()), inputs.end());
  if (inputs.empty())
    return SetId{};
  if (inputs.size() == 1)
    return inputs.front();
  if (auto it = unions.find(ArrayRef<SetId>(inputs)); it != unions.end())
    return it->second;
  SetId largest = *llvm::max_element(
      inputs, [&](SetId a, SetId b) { return members(a).size() < members(b).size(); });
  SetId result = largest;
  if (!llvm::all_of(inputs, [&](SetId part) { return part == largest || within(part, largest); })) {
    SmallVector<Label> all;
    for (SetId part : inputs)
      llvm::append_range(all, members(part));
    llvm::sort(all);
    all.erase(std::unique(all.begin(), all.end()), all.end());
    result = intern(all);
  }
  unions.try_emplace(ArrayRef<SetId>(inputs).copy(storage), result);
  return result;
}

//===----------------------------------------------------------------------===//
// The union-find and the edges
//===----------------------------------------------------------------------===//

Graph::Graph(const SymbolTable &table) : out(table) {}

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

// The labels by name, each a rank; each class holds the labels that start
// at its points.
void Graph::rank() {
  for (const auto &source : sources)
    labelNames.push_back(source.second);
  llvm::sort(labelNames, byName);
  labelNames.erase(std::unique(labelNames.begin(), labelNames.end()), labelNames.end());
  llvm::DenseMap<StringAttr, Label> ranks;
  for (auto [position, label] : llvm::enumerate(labelNames))
    ranks.try_emplace(label.getAttr(), Label(static_cast<std::uint32_t>(position)));
  std::vector<std::pair<Node, Label>> starts;
  for (const auto &[node, label] : sources)
    starts.emplace_back(find(node), ranks.at(label.getAttr()));
  sources = {};
  llvm::sort(starts);
  starts.erase(std::unique(starts.begin(), starts.end()), starts.end());
  for (auto first = starts.begin(); first != starts.end();) {
    Node root = first->first;
    auto last = std::find_if(first, starts.end(), [&](const auto &start) { return start.first != root; });
    SmallVector<Label> own;
    for (auto it = first; it != last; ++it)
      own.push_back(it->second);
    SmallVector<SetId, 2> both = {classes[at(root)].labels, sets.intern(own)};
    classes[at(root)].labels = sets.unite(both);
    first = last;
  }
}

// One wave: the classes downstream of a node the last wave left owed, its
// cycles collapsed, each set computed after the sets it includes; then
// the firings the dispatches owe.
SmallVector<Firing> Graph::wave() {
  // The classes the wave takes, as roots, each once: those owed, and every
  // class that includes one taken.
  llvm::DenseMap<Node, unsigned> vertexOf;
  SmallVector<Node> order;
  auto take = [&](Node node) {
    Node root = find(node);
    if (vertexOf.try_emplace(root, static_cast<unsigned>(order.size())).second)
      order.push_back(root);
  };
  for (Node node : dirty)
    take(node);
  dirty.clear();
  for (size_t v = 0; v < order.size(); ++v)
    for (Node next : classes[at(order[v])].successors)
      take(next);

  // Each class's successors as the wave's roots, each once, itself never.
  auto n = static_cast<unsigned>(order.size());
  SmallVector<SmallVector<unsigned>> edges(n);
  std::vector<unsigned> seen(n, n);
  for (unsigned v = 0; v < n; ++v) {
    SmallVector<Node, 2> kept;
    for (Node next : classes[at(order[v])].successors) {
      unsigned w = vertexOf.at(find(next));
      if (w == v || seen[w] == v)
        continue;
      seen[w] = v;
      edges[v].push_back(w);
      kept.push_back(order[w]);
    }
    classes[at(order[v])].successors = std::move(kept);
  }

  // What each class is owed besides the sets it held: the sets of the
  // edges added since the last wave, and of the classes it includes whose
  // sets grow in this one.
  std::vector<SmallVector<SetId, 1>> owed(n);
  for (auto [from, to] : added)
    owed[vertexOf.at(find(to))].push_back(classes[at(find(from))].labels);
  added.clear();
  std::vector<SetId> before(n);
  for (unsigned v = 0; v < n; ++v)
    before[v] = classes[at(order[v])].labels;

  // The components come callees first, so the last includes no other
  // class of the wave; each is one class once its members merge. A member
  // whose set did not grow owes its successors nothing new.
  SmallVector<SmallVector<unsigned>> parts = components(edges);
  std::vector<unsigned> partOf(n);
  for (auto [i, part] : llvm::enumerate(parts))
    for (unsigned v : part)
      partOf[v] = static_cast<unsigned>(i);
  for (auto i = static_cast<unsigned>(parts.size()); i-- > 0;) {
    ArrayRef<unsigned> part = parts[i];
    SmallVector<SetId, 4> inputs;
    for (unsigned v : part) {
      inputs.push_back(before[v]);
      llvm::append_range(inputs, owed[v]);
    }
    Node root = order[part.front()];
    for (unsigned v : part.drop_front())
      root = merge(root, order[v]);
    SetId set = sets.unite(inputs);
    classes[at(root)].labels = set;
    for (unsigned v : part)
      if (set != before[v])
        for (unsigned w : edges[v])
          if (partOf[w] != i)
            owed[w].push_back(set);
  }

  // Each dispatch runs the labels its callee holds that it has not run: it
  // has run a subset of them.
  SmallVector<Firing> firings;
  for (auto [d, run] : llvm::enumerate(runs)) {
    SetId set = classes[at(find(run.callee))].labels;
    if (set == run.ran)
      continue;
    SmallVector<Label> unrun;
    ArrayRef<Label> now = sets.members(set), had = sets.members(run.ran);
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
  Builder builder(*this);
  readFiring(out.table, runs[at(run)].call, labelNames[at(label)], builder);
}

// Every node's labels are its root's, one attribute per set: its labels
// in rank order, which is name order.
Solution Graph::solve() && {
  rank();
  for (SmallVector<Firing> firings = wave(); !firings.empty(); firings = wave())
    for (Firing firing : firings)
      fire(firing);
  llvm::DenseMap<SetId, ArrayAttr> attrs;
  auto n = static_cast<unsigned>(parents.size());
  out.labels.assign(n, out.empty);
  for (unsigned node = 0; node < n; ++node) {
    SetId set = classes[at(find(Node(node)))].labels;
    if (set == SetId{})
      continue;
    auto [it, made] = attrs.try_emplace(set);
    if (made) {
      SmallVector<Attribute> names;
      for (Label label : sets.members(set))
        names.push_back(labelNames[at(label)]);
      it->second = ArrayAttr::get(out.empty.getContext(), names);
    }
    out.labels[node] = it->second;
  }
  return std::move(out);
}

//===----------------------------------------------------------------------===//
// Answers
//===----------------------------------------------------------------------===//

Solution::Solution(const SymbolTable &table)
    : table(table), empty(ArrayAttr::get(table.getOp()->getContext(), {})) {}

ArrayAttr Solution::labelsOf(const PointKey &key) const {
  auto it = nodes.find(key);
  return it == nodes.end() ? empty : labels[at(it->second)];
}

std::optional<FlowPoint> Solution::sinkOf(OpOperand &operand) const {
  if (auto it = sinks.find(&operand); it != sinks.end())
    return it->second;
  return std::nullopt;
}

bool within(ArrayAttr a, ArrayAttr b) {
  return a == b || llvm::all_of(a, [&](Attribute label) {
           return std::binary_search(b.begin(), b.end(), label, byName);
         });
}

std::optional<unsigned> positionIn(ArrayAttr set, FlatSymbolRefAttr label) {
  ArrayRef<Attribute> labels = set.getValue();
  const Attribute *it = llvm::lower_bound(labels, Attribute(label), byName);
  if (it == labels.end() || *it != label)
    return std::nullopt;
  return static_cast<unsigned>(it - labels.begin());
}

} // namespace idr::labels

namespace idr {

Labels::Labels(Operation *program, AnalysisManager &am) : solution([&] {
  labels::Graph graph(am.getAnalysis<SymbolTable>());
  graph.walk(program);
  return std::move(graph).solve();
}()) {}

} // namespace idr
