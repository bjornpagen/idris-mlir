// idr.graph:scc: strongly connected components, for the passes that must
// find the cycles of a graph: idr-defunctionalize (closure types that
// contain themselves), idr-loop-breakers and idr-inline (cycles of
// references among functions), and the analyses that go through a call
// graph callees first. The graphs are the passes' own (a reference by a
// closure is an edge, a loop breaker is none), not MLIR's CallGraph, so they
// are handed to LLVM's iterative Tarjan (scc_iterator) as a graph of
// indices: a call chain of any depth takes no recursion.
export module idr.graph:scc;

import idr.mlir;

export namespace idr::graph {

// The strongly connected components of the graph whose vertices are the
// indices of `successors` and whose edges go from `v` to each of
// `successors[v]`, in reverse topological order. The result depends only on
// the order of each successor list.
llvm::SmallVector<llvm::SmallVector<unsigned>>
components(llvm::ArrayRef<llvm::SmallVector<unsigned>> successors);

// The strongly connected components of the graph whose nodes are `nodes`
// and whose edges go from `n` to each of `successors(n)` that is a node, in
// reverse topological order. The result depends only on the order of
// `nodes` and of each successor list. Each user instantiates the template,
// so its body is here: it numbers the nodes, and `components` does the work.
template <typename Node>
llvm::SmallVector<llvm::SmallVector<Node>>
stronglyConnected(llvm::ArrayRef<Node> nodes,
                  llvm::function_ref<llvm::SmallVector<Node>(Node)> successors) {
  llvm::SmallVector<Node> order;
  llvm::DenseMap<Node, unsigned> index;
  for (Node node : nodes)
    if (index.try_emplace(node, order.size()).second)
      order.push_back(node);
  llvm::SmallVector<llvm::SmallVector<unsigned>> edges(order.size());
  for (auto [at, node] : llvm::enumerate(order))
    for (Node next : successors(node))
      if (auto found = index.find(next); found != index.end())
        edges[at].push_back(found->second);
  llvm::SmallVector<llvm::SmallVector<Node>> out;
  for (const llvm::SmallVector<unsigned> &component : components(edges)) {
    llvm::SmallVector<Node> &nodesOf = out.emplace_back();
    for (unsigned vertex : component)
      nodesOf.push_back(order[vertex]);
  }
  return out;
}

} // namespace idr::graph
