// Strongly connected components (Tarjan), for the passes that must find the
// cycles of a graph: idr-defunctionalize (closure types that contain
// themselves) and idr-loop-breakers (cycles of references among functions).
#pragma once

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>

namespace idr::passes {

// The strongly connected components of the graph whose nodes are `nodes`
// and whose edges go from `n` to each of `successors(n)` that is a node, in
// reverse topological order. The result depends only on the order of
// `nodes` and of each successor list.
template <typename Node>
llvm::SmallVector<llvm::SmallVector<Node>>
stronglyConnected(llvm::ArrayRef<Node> nodes,
                  llvm::function_ref<llvm::SmallVector<Node>(Node)> successors) {
  llvm::DenseSet<Node> inGraph(nodes.begin(), nodes.end());
  llvm::DenseMap<Node, unsigned> index, low;
  llvm::SmallVector<Node> stack;
  llvm::DenseSet<Node> onStack;
  llvm::SmallVector<llvm::SmallVector<Node>> components;
  unsigned counter = 0;
  auto visit = [&](auto &self, Node v) -> void {
    index[v] = counter;
    low[v] = counter++;
    stack.push_back(v);
    onStack.insert(v);
    for (Node w : successors(v)) {
      if (!inGraph.contains(w))
        continue;
      if (!index.count(w)) {
        self(self, w);
        low[v] = std::min(low[v], low[w]);
      } else if (onStack.contains(w)) {
        low[v] = std::min(low[v], index[w]);
      }
    }
    if (low[v] != index[v])
      return;
    llvm::SmallVector<Node> &component = components.emplace_back();
    Node w;
    do {
      w = stack.pop_back_val();
      onStack.erase(w);
      component.push_back(w);
    } while (w != v);
  };
  for (Node v : nodes)
    if (!index.count(v))
      visit(visit, v);
  return components;
}

} // namespace idr::passes
