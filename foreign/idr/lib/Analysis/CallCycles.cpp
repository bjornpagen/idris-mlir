// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cycles of calls, read off upstream's call graph by upstream's walk,
// with every function the graph has no node for in a component of its own.
#include "idr/Analysis/CallCycles.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <utility>

using namespace mlir;

idr::CallCycles::CallCycles(Operation *op, AnalysisManager &am) {
  // Appends `component` to the partition, its members numbered by it.
  auto append = [&](Component component) -> const Component & {
    auto at = static_cast<unsigned>(all.size());
    for (Operation *member : component)
      indices.try_emplace(member, at);
    return all.emplace_back(std::move(component));
  };
  // First the functions with no body, each alone: it calls nothing, so it
  // comes before every caller. A function with a body is a node of the
  // graph, which the walk below meets, and its body declares no function,
  // so this walk does not enter it.
  op->walk<WalkOrder::PreOrder>([&](CallableOpInterface fn) {
    if (fn.getCallableRegion())
      return WalkResult::skip();
    append({fn.getOperation()});
    return WalkResult::advance();
  });
  const CallGraph &graph = am.getAnalysis<CallGraph>();
  for (auto scc = llvm::scc_begin(&graph); !scc.isAtEnd(); ++scc) {
    // The two external nodes, the caller of every callable and the callee
    // of a call no node resolves, are each a component of their own: no
    // edge enters the first, and none leaves the second.
    if ((*scc).front()->isExternal())
      continue;
    const Component &component = append(llvm::map_to_vector<1>(
        *scc, [](CallGraphNode *node) { return node->getCallableRegion()->getParentOp(); }));
    if (component.size() == 1 && scc.hasCycle())
      selfCalling.insert(component.front());
  }
}

bool idr::CallCycles::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<CallCycles>() || !pa.isPreserved<CallGraph>();
}

unsigned idr::CallCycles::componentOf(Operation *fn) const { return indices.at(fn); }

bool idr::CallCycles::together(Operation *a, Operation *b) const {
  return componentOf(a) == componentOf(b);
}

bool idr::CallCycles::callsItself(Operation *fn) const { return selfCalling.contains(fn); }
