// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The label solve: a worklist over the classes of a union-find, each class
// holding its set of labels, the set it has sent on, the nodes its labels
// flow into and the dispatches its labels run. A class sends only what it
// gained since it last sent; a dispatch adds the edges of each label as it
// arrives; two classes that hold one cell are merged, never coerced. The
// sets are the least solution of the edges, so they do not depend on the
// walk's or the worklist's order.
//
// Only a class's sets are made, each once per distinct content: what a
// class gains and what it sends are differences computed where they are
// used and never kept, so the table of sets grows with what the classes
// hold and not with the traffic between them. The worklist ends because a
// class is queued only when its set grew or two classes merged, a set only
// grows within the program's finite set of labels, and the classes only
// merge.

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/DenseSet.h"

#include <algorithm>
#include <iterator>

using namespace mlir;

namespace idr::labels {

//===----------------------------------------------------------------------===//
// Labels and sets
//===----------------------------------------------------------------------===//

// A label's number, given when it is first met.
Label Graph::labelId(FlatSymbolRefAttr label) {
  auto [it, made] = labelIds.try_emplace(label.getAttr(), static_cast<Label>(labelNames.size()));
  if (made)
    labelNames.push_back(label);
  return it->second;
}

// The set of `ids`, sorted, made once: two equal sets are one number.
SetId Graph::intern(ArrayRef<Label> ids) {
  if (ids.empty())
    return 0;
  if (auto it = setIds.find(ids); it != setIds.end())
    return it->second;
  Label *kept = storage.Allocate<Label>(ids.size());
  std::copy(ids.begin(), ids.end(), kept);
  ArrayRef<Label> made(kept, ids.size());
  SetId id = static_cast<SetId>(sets.size());
  sets.push_back(made);
  setIds.try_emplace(made, id);
  return id;
}

//===----------------------------------------------------------------------===//
// The union-find and the edges
//===----------------------------------------------------------------------===//

Node Graph::find(Node node) const {
  Node root = node;
  while (parents[root] != root)
    root = parents[root];
  while (parents[node] != root) {
    Node next = parents[node];
    parents[node] = root;
    node = next;
  }
  return root;
}

// A flow of a lazy carrier joins two points that hold one cell; any other
// is an inclusion.
void Graph::link(Node from, Node to, bool lazy) {
  if (lazy)
    unify(from, to);
  else
    include(from, to);
}

// A successor added now is given the whole set at once, so it is owed
// nothing of what the class sent before.
void Graph::include(Node from, Node to) {
  Node source = find(from);
  if (source == find(to))
    return;
  classes[source].successors.push_back(to);
  addLabels(to, sets[classes[source].set]);
}

// One class for both. Each side's successors and dispatches have been given
// what that side sent; the merged lists have been given what both sides
// sent, so the merged class owes them its set less that. A successor met
// twice, or one in the merged class itself, is kept once or dropped: it
// would only be given the same labels again.
void Graph::unify(Node a, Node b) {
  Node x = find(a), y = find(b);
  if (x == y)
    return;
  Class &into = classes[x];
  Class &from = classes[y];
  ArrayRef<Label> intoSet = sets[into.set], fromSet = sets[from.set];
  ArrayRef<Label> intoSent = sets[into.sent], fromSent = sets[from.sent];
  SmallVector<Label> both, sent;
  std::set_union(intoSet.begin(), intoSet.end(), fromSet.begin(), fromSet.end(),
                 std::back_inserter(both));
  std::set_intersection(intoSent.begin(), intoSent.end(), fromSent.begin(), fromSent.end(),
                        std::back_inserter(sent));
  parents[y] = x;
  into.set = intern(both);
  into.sent = intern(sent);
  llvm::append_range(into.successors, from.successors);
  llvm::append_range(into.dispatches, from.dispatches);
  from = Class();
  llvm::SmallDenseSet<Node, 8> roots;
  llvm::erase_if(into.successors, [&](Node next) {
    Node root = find(next);
    return root == x || !roots.insert(root).second;
  });
  queue(x);
}

// `labels`, sorted by number, arrive at `to`'s class, which takes what it
// lacks.
void Graph::addLabels(Node to, ArrayRef<Label> labels) {
  if (labels.empty())
    return;
  Node root = find(to);
  ArrayRef<Label> held = sets[classes[root].set];
  SmallVector<Label> merged;
  std::set_union(held.begin(), held.end(), labels.begin(), labels.end(),
                 std::back_inserter(merged));
  if (merged.size() == held.size())
    return;
  classes[root].set = intern(merged);
  queue(root);
}

void Graph::queue(Node root) {
  Class &owing = classes[root];
  if (owing.queued || owing.set == owing.sent)
    return;
  owing.queued = true;
  worklist.push_back(root);
}

// Each label of `labels` the dispatch has not yet run takes the call's
// arguments after its captures and gives its results to the call's.
void Graph::fire(unsigned index, ArrayRef<Label> labels) {
  for (Label id : labels) {
    if (!dispatches[index].handled.insert(id).second)
      continue;
    CallOpInterface call = dispatches[index].call;
    FlatSymbolRefAttr label = labelNames[id];
    auto fn = table.lookup<FuncOp>(label.getAttr());
    Operation::operand_range args = call.getArgOperands();
    assert(fn && fn.getNumArguments() >= args.size() &&
           "a label fits the carrier of the callee that holds it");
    unsigned captures = fn.getNumArguments() - static_cast<unsigned>(args.size());
    for (auto [i, arg] : llvm::enumerate(args))
      if (carriesLabels(arg.getType()))
        link(nodeOf(FlowPoint::of(arg)),
             nodeOf(FlowPoint::parameter(label, captures + static_cast<unsigned>(i))),
             isLazyType(arg.getType()));
    for (auto [j, result] : llvm::enumerate(call->getResults()))
      if (carriesLabels(result.getType()))
        link(nodeOf(FlowPoint::result(label, static_cast<unsigned>(j))),
             nodeOf(FlowPoint::of(result)), isLazyType(result.getType()));
  }
}

void Graph::solve() {
  while (!worklist.empty()) {
    Node node = worklist.back();
    worklist.pop_back();
    // A class merged away is its root's now, which the merge queued.
    if (find(node) != node)
      continue;
    Class &owing = classes[node];
    owing.queued = false;
    if (owing.set == owing.sent)
      continue;
    ArrayRef<Label> set = sets[owing.set], sent = sets[owing.sent];
    SmallVector<Label> gained;
    std::set_difference(set.begin(), set.end(), sent.begin(), sent.end(),
                        std::back_inserter(gained));
    owing.sent = owing.set;
    // The lists are walked as they were: a dispatch may merge this class
    // into another, which then owes the merged lists what both sides had
    // not sent, and what is added to them meanwhile was given the whole
    // set when it was added.
    SmallVector<Node> successors = llvm::to_vector(owing.successors);
    SmallVector<unsigned> runs = llvm::to_vector(owing.dispatches);
    for (Node next : successors)
      addLabels(next, gained);
    for (unsigned run : runs)
      fire(run, gained);
  }
  freeze();
}

// Every node names its root, so a later find writes nothing; every root's
// set, and the empty set, has its attribute, each labels in name order.
void Graph::freeze() {
  for (Node node = 0, n = static_cast<Node>(parents.size()); node < n; ++node)
    parents[node] = find(node);
  SmallVector<SetId> roots{0};
  for (Node node = 0, n = static_cast<Node>(parents.size()); node < n; ++node)
    if (parents[node] == node)
      roots.push_back(classes[node].set);
  for (SetId set : roots) {
    if (attrs.count(set))
      continue;
    SmallVector<FlatSymbolRefAttr> names;
    for (Label id : sets[set])
      names.push_back(labelNames[id]);
    llvm::sort(names, [](FlatSymbolRefAttr a, FlatSymbolRefAttr b) {
      return a.getValue() < b.getValue();
    });
    attrs.try_emplace(set,
                      ArrayAttr::get(context, SmallVector<Attribute>(names.begin(), names.end())));
  }
}

//===----------------------------------------------------------------------===//
// Answers
//===----------------------------------------------------------------------===//

// A set's labels in name order: one attribute per set, made when the solve
// froze.
ArrayAttr Graph::attrOf(SetId set) const {
  auto it = attrs.find(set);
  assert(it != attrs.end() && "every root's set has its attribute");
  return it->second;
}

ArrayAttr Graph::labelsOf(const FlowPoint &point) const {
  std::optional<Node> node = lookup(point);
  return attrOf(node ? classes[find(*node)].set : 0);
}

ArrayAttr Graph::labelsOf(const FlowAnchor &anchor) const {
  std::optional<Node> node = lookup(anchor);
  return attrOf(node ? classes[find(*node)].set : 0);
}

} // namespace idr::labels

namespace idr {

Labels::Labels(Operation *program, AnalysisManager &am) : graph(am.getAnalysis<SymbolTable>()) {
  graph.walk(program);
  graph.solve();
}

ArrayAttr Labels::labelsOf(Value value) const {
  return graph.labelsOf(FlowPoint::of(value));
}

ArrayAttr Labels::labelsOf(const FlowPoint &point) const { return graph.labelsOf(point); }

ArrayAttr Labels::labelsOf(const FlowAnchor &anchor) const { return graph.labelsOf(anchor); }

ArrayAttr Labels::runs(Operation *op) const {
  if (auto apply = dyn_cast<ApplyOp>(op))
    return labelsOf(apply.getCallee());
  if (auto force = dyn_cast<ForceOp>(op))
    return labelsOf(force.getSuspension());
  return graph.attrOf(0);
}

} // namespace idr
