// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The label solve: a worklist over the classes of a union-find, each class
// holding its set of labels, the nodes its labels flow into and the
// dispatches its labels run. A class sends only what it gained since it
// last sent; a dispatch adds the edges of each label as it arrives; two
// classes that hold one cell are merged, never coerced. The sets are the
// least solution of the edges, so they do not depend on the walk's or the
// worklist's order.

#include "idr/Analysis/Labels.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>

using namespace mlir;

namespace idr::labels {

//===----------------------------------------------------------------------===//
// Labels and sets
//===----------------------------------------------------------------------===//

// A label's number, given when it is first met.
std::uint32_t Graph::labelId(FlatSymbolRefAttr label) {
  auto [it, made] =
      labelIds.try_emplace(label.getAttr(), static_cast<std::uint32_t>(labelNames.size()));
  if (made)
    labelNames.push_back(label);
  return it->second;
}

// The set of `ids`, sorted, made once: two equal sets are one number.
SetId Graph::intern(ArrayRef<std::uint32_t> ids) {
  if (ids.empty())
    return 0;
  if (auto it = setIds.find(ids); it != setIds.end())
    return it->second;
  std::uint32_t *kept = storage.Allocate<std::uint32_t>(ids.size());
  std::copy(ids.begin(), ids.end(), kept);
  ArrayRef<std::uint32_t> made(kept, ids.size());
  SetId id = static_cast<SetId>(sets.size());
  sets.push_back(made);
  setIds.try_emplace(made, id);
  return id;
}

SetId Graph::join(SetId a, SetId b) {
  if (a == b || b == 0)
    return a;
  if (a == 0)
    return b;
  auto key = a < b ? std::make_pair(a, b) : std::make_pair(b, a);
  if (auto it = joins.find(key); it != joins.end())
    return it->second;
  SmallVector<std::uint32_t> merged;
  std::set_union(sets[a].begin(), sets[a].end(), sets[b].begin(), sets[b].end(),
                 std::back_inserter(merged));
  SetId out = intern(merged);
  joins.try_emplace(key, out);
  return out;
}

SetId Graph::minus(SetId a, SetId b) {
  if (a == 0 || b == 0 || a == b)
    return a == b ? 0 : a;
  SmallVector<std::uint32_t> left;
  std::set_difference(sets[a].begin(), sets[a].end(), sets[b].begin(), sets[b].end(),
                      std::back_inserter(left));
  return intern(left);
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

void Graph::include(Node from, Node to) {
  Node source = find(from);
  if (source == find(to))
    return;
  classes[source].successors.push_back(to);
  addLabels(to, classes[source].set);
}

// One class for both. Each side's successors and dispatches have seen its
// own set but what it had pending; the merged class owes each of them the
// other's labels too, so it holds as pending everything only one side had
// and both sides' pending. A receiver takes only what it lacks.
void Graph::unify(Node a, Node b) {
  Node x = find(a), y = find(b);
  if (x == y)
    return;
  SetId owed = join(join(classes[x].pending, classes[y].pending),
                    join(minus(classes[x].set, classes[y].set),
                         minus(classes[y].set, classes[x].set)));
  parents[y] = x;
  Class &into = classes[x];
  Class &from = classes[y];
  into.set = join(into.set, from.set);
  into.pending = owed;
  llvm::append_range(into.successors, from.successors);
  llvm::append_range(into.dispatches, from.dispatches);
  from = Class();
  if (into.pending && !into.queued) {
    into.queued = true;
    worklist.push_back(x);
  }
}

void Graph::addLabels(Node to, SetId set) {
  if (set == 0)
    return;
  Node root = find(to);
  SetId added = minus(set, classes[root].set);
  if (added == 0)
    return;
  Class &target = classes[root];
  target.set = join(target.set, added);
  target.pending = join(target.pending, added);
  if (!target.queued) {
    target.queued = true;
    worklist.push_back(root);
  }
}

// Each label of `set` the dispatch has not yet run takes the call's
// arguments after its captures and gives its results to the call's.
void Graph::fire(unsigned index, SetId set) {
  for (std::uint32_t id : sets[set]) {
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
      if (isKeyed(arg.getType()))
        link(nodeOf(FlowPoint::of(arg)),
             nodeOf(FlowPoint::parameter(label, captures + static_cast<unsigned>(i))),
             isLazyType(arg.getType()));
    for (auto [j, result] : llvm::enumerate(call->getResults()))
      if (isKeyed(result.getType()))
        link(nodeOf(FlowPoint::result(label, static_cast<unsigned>(j))),
             nodeOf(FlowPoint::of(result)), isLazyType(result.getType()));
  }
}

void Graph::solve() {
  while (!worklist.empty()) {
    Node node = worklist.back();
    worklist.pop_back();
    // A class merged away handed its pending labels to its root, which was
    // queued then.
    if (find(node) != node)
      continue;
    classes[node].queued = false;
    SetId sent = classes[node].pending;
    classes[node].pending = 0;
    if (sent == 0)
      continue;
    // The lists are walked as they were: a dispatch may merge this class
    // into another, which then owes its lists what either side lacked, and
    // what is added to them meanwhile was given the whole set when it was
    // added.
    SmallVector<Node> successors = llvm::to_vector(classes[node].successors);
    SmallVector<unsigned> runs = llvm::to_vector(classes[node].dispatches);
    for (Node next : successors)
      addLabels(next, sent);
    for (unsigned run : runs)
      fire(run, sent);
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
    for (std::uint32_t id : sets[set])
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

} // namespace idr::labels

namespace idr {

Labels::Labels(Operation *module, AnalysisManager &am) : graph(am.getAnalysis<SymbolTable>()) {
  graph.walk(module);
  graph.solve();
}

ArrayAttr Labels::labelsOf(Value value) const {
  return graph.labelsOf(FlowPoint::of(value));
}

ArrayAttr Labels::labelsOf(const FlowPoint &point) const { return graph.labelsOf(point); }

ArrayAttr Labels::runs(Operation *op) const {
  if (auto apply = dyn_cast<ApplyOp>(op))
    return labelsOf(apply.getCallee());
  if (auto force = dyn_cast<ForceOp>(op); force && isLazyType(force.getSuspension().getType()))
    return labelsOf(force.getSuspension());
  return graph.attrOf(0);
}

} // namespace idr
