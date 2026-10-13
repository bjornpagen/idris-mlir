// Strongly connected components, for every graph of ours that must find its
// cycles or be gone through callees first: the references among functions,
// the containment among types, the keys of closure sums. The graphs are our
// own (a reference by a closure is an edge, a loop breaker is none), not
// MLIR's CallGraph, so they are handed to LLVM's iterative Tarjan as a graph
// of indices: a chain of any depth takes no recursion.
#ifndef IDR_SUPPORT_SCC_H
#define IDR_SUPPORT_SCC_H

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {

// The strongly connected components of the graph whose vertices are the
// indices of `successors` and whose edges go from `v` to each of
// `successors[v]`, in reverse topological order: callees first. The result
// depends only on the order of each successor list.
llvm::SmallVector<llvm::SmallVector<unsigned>>
components(llvm::ArrayRef<llvm::SmallVector<unsigned>> successors);

// The strongly connected components of the graph whose nodes are `nodes`
// and whose edges go from `n` to each of `successors(n)` that is a node, in
// reverse topological order. The result depends only on the order of
// `nodes` and of each successor list. Each user instantiates the template,
// so it stays thin: it numbers the nodes, and `components` does the work.
template <typename Node>
llvm::SmallVector<llvm::SmallVector<Node>>
stronglyConnected(llvm::ArrayRef<Node> nodes,
                  llvm::function_ref<llvm::SmallVector<Node>(Node)> successors) {
  llvm::SmallVector<Node> order;
  llvm::DenseMap<Node, unsigned> index;
  for (Node node : nodes)
    if (index.try_emplace(node, static_cast<unsigned>(order.size())).second)
      order.push_back(node);
  llvm::SmallVector<llvm::SmallVector<unsigned>> edges(order.size());
  for (unsigned at = 0, n = static_cast<unsigned>(order.size()); at < n; ++at)
    for (Node next : successors(order[at]))
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

} // namespace idr

#endif // IDR_SUPPORT_SCC_H
