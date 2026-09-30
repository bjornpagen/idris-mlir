// Strongly connected components, for the passes that must find the cycles
// of a graph: idr-defunctionalize (closure types that contain themselves),
// idr-loop-breakers and idr-inline (cycles of references among functions),
// and the analyses that go through a call graph callees first. The graphs
// are the passes' own (a reference by a closure is an edge, a loop breaker
// is none), not MLIR's CallGraph, so they are handed to LLVM's iterative
// Tarjan (scc_iterator) as a graph of indices: a call chain of any depth
// takes no recursion.
#pragma once

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/GraphTraits.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <vector>

namespace idr::passes::detail {

// A node of the graph LLVM walks, with its successors.
struct Vertex {
  llvm::SmallVector<const Vertex *> successors;
};

} // namespace idr::passes::detail

template <> struct llvm::GraphTraits<const idr::passes::detail::Vertex *> {
  using NodeRef = const idr::passes::detail::Vertex *;
  using ChildIteratorType = llvm::SmallVector<NodeRef>::const_iterator;
  static NodeRef getEntryNode(NodeRef vertex) { return vertex; }
  static ChildIteratorType child_begin(NodeRef vertex) { return vertex->successors.begin(); }
  static ChildIteratorType child_end(NodeRef vertex) { return vertex->successors.end(); }
};

namespace idr::passes {

// The strongly connected components of the graph whose nodes are `nodes`
// and whose edges go from `n` to each of `successors(n)` that is a node, in
// reverse topological order. The result depends only on the order of
// `nodes` and of each successor list.
template <typename Node>
llvm::SmallVector<llvm::SmallVector<Node>>
stronglyConnected(llvm::ArrayRef<Node> nodes,
                  llvm::function_ref<llvm::SmallVector<Node>(Node)> successors) {
  llvm::SmallVector<Node> order;
  llvm::DenseMap<Node, unsigned> index;
  for (Node node : nodes)
    if (index.try_emplace(node, order.size()).second)
      order.push_back(node);
  // One more vertex, the root, precedes every node in order, so that one
  // walk from it visits them all; nothing reaches it, so its component is
  // itself, and the last.
  std::vector<detail::Vertex> vertices(order.size() + 1);
  const detail::Vertex *root = &vertices.back();
  for (auto [at, node] : llvm::enumerate(order)) {
    vertices.back().successors.push_back(&vertices[at]);
    for (Node next : successors(node))
      if (auto found = index.find(next); found != index.end())
        vertices[at].successors.push_back(&vertices[found->second]);
  }
  llvm::SmallVector<llvm::SmallVector<Node>> components;
  for (auto it = llvm::scc_begin(root); !it.isAtEnd(); ++it) {
    if ((*it).front() == root)
      continue;
    llvm::SmallVector<Node> &component = components.emplace_back();
    for (const detail::Vertex *vertex : *it)
      component.push_back(order[static_cast<size_t>(vertex - vertices.data())]);
  }
  return components;
}

} // namespace idr::passes
