// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The marking: every node reachable from the seeds, in one direction, a
// node that rises walking its row once. Its clients (exclusivity,
// allocation into a lifetime, borrows, the obligation closure) share the
// loop here, instantiated once per graph type.
//
// The answer is the BitSet the loop raises as it goes, and its worklist
// a footprint vector, so a pass's footprint counts both. A node is pushed
// only when the set rose by it, which the set says, and it rises once, so
// the loop visits each node and each edge at most once.
//
// A marking cannot fail and cannot stop early: its answer is a set that
// only rises, and the loop ends when the worklist is empty. A solve unit of
// one is traced, never skipped (Trace.h).
#ifndef IDR_ANALYSIS_SOLVER_MARK_H
#define IDR_ANALYSIS_SOLVER_MARK_H

#include "idr/Analysis/Solver/Graph.h"
#include "idr/Support/Changed.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include <span>

namespace idr {

// The nodes reachable from `seeds` along `g`'s rows of direction `D`, seeds
// included.
template <Direction D, class Tag>
BitSet<Id<Tag>> mark(const Csr<Tag> &g, std::span<const Id<Tag>> seeds) {
  using Node = Id<Tag>;
  BitSet<Node> marked(g.size());
  footprint::Vector<Node> work;
  auto rise = [&](Node node) {
    if (marked.raise(node) == Changed::Yes)
      work.push_back(node);
  };
  for (Node seed : seeds)
    rise(seed);
  while (!work.empty()) {
    Node node = work.back();
    work.pop_back();
    for (Node next : g.next(node, D{}))
      rise(next);
  }
  return marked;
}

} // namespace idr

#endif // IDR_ANALYSIS_SOLVER_MARK_H
