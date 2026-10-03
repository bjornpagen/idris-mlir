// Strongly connected components of a graph of indices, by LLVM's iterative
// Tarjan.
module idr.graph;

import idr.mlir;

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
idr::graph::components(llvm::ArrayRef<llvm::SmallVector<unsigned>> successors) {
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
