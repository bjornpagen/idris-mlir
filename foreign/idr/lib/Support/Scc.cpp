// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one walk over a graph of ours: every such graph's components come
// through `idr::components`, so this is the one place that shapes a graph
// of indices for LLVM's iterative Tarjan (scc_iterator). Upstream's call
// graph has GraphTraits of its own, which CallCycles walks.
#include "idr/Support/Scc.h"

#include "llvm/ADT/GraphTraits.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"

#include <vector>

namespace {

// A node of the graph LLVM walks, with its successors.
struct Vertex {
  llvm::SmallVector<const Vertex *> successors;
};

} // namespace

template <> struct llvm::GraphTraits<const Vertex *> {
  using NodeRef = const Vertex *;
  using ChildIteratorType = llvm::SmallVector<NodeRef>::const_iterator;
  static NodeRef getEntryNode(NodeRef vertex) { return vertex; }
  static ChildIteratorType child_begin(NodeRef vertex) { return vertex->successors.begin(); }
  static ChildIteratorType child_end(NodeRef vertex) { return vertex->successors.end(); }
};

llvm::SmallVector<llvm::SmallVector<unsigned>>
idr::components(llvm::ArrayRef<llvm::SmallVector<unsigned>> successors) {
  // One more vertex, the root, precedes every vertex in order, so that one
  // walk from it visits them all; nothing reaches it, so its component is
  // itself, and the last.
  std::vector<Vertex> vertices(successors.size() + 1);
  const Vertex *root = &vertices.back();
  for (auto [at, next] : llvm::enumerate(successors)) {
    vertices.back().successors.push_back(&vertices[at]);
    for (unsigned to : next)
      vertices[at].successors.push_back(&vertices[to]);
  }
  llvm::SmallVector<llvm::SmallVector<unsigned>> out;
  for (auto it = llvm::scc_begin(root); !it.isAtEnd(); ++it) {
    if ((*it).front() == root)
      continue;
    llvm::SmallVector<unsigned> &component = out.emplace_back();
    for (const Vertex *vertex : *it)
      component.push_back(static_cast<unsigned>(vertex - vertices.data()));
  }
  return out;
}
