// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One walk of LLVM's Tarjan from the sentinel root, compiled once for every
// graph of ours. The root reaches every node and nothing reaches the root,
// so its component is the last the walk gives, and it is no component of
// the graph.
#include "idr/Analysis/Solver/Components.h"

#include "llvm/ADT/SCCIterator.h"

namespace idr::detail {

RawPartition componentsOf(Rows forward, std::uint32_t count) {
  RawPartition out;
  out.order.reserve(count);
  out.componentOf.assign(count, 0);
  out.start.push_back(0);
  RowGraph graph{forward, count};
  for (auto scc = llvm::scc_begin(static_cast<const RowGraph *>(&graph)); !scc.isAtEnd();
       ++scc) {
    const std::vector<RowNode> &members = *scc;
    if (members.front().node == count)
      continue;
    auto component = static_cast<std::uint32_t>(out.start.size() - 1);
    for (RowNode member : members) {
      out.componentOf[member.node] = component;
      out.order.push_back(member.node);
    }
    out.start.push_back(static_cast<std::uint32_t>(out.order.size()));
  }
  return out;
}

} // namespace idr::detail
