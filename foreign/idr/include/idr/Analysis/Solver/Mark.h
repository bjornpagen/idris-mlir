// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The marking: every node reachable from the seeds, in one direction, a
// node that rises walking its row once. Its clients (exclusivity,
// allocation into a lifetime, borrows, the obligation closure) share the
// two loops here, each instantiated once per graph type.
//
// The answer is the BitSet the loop raises as it goes, and its worklist
// a footprint vector, so a pass's footprint counts both. A node is pushed
// only when the set rose by it, which the set says, and it rises once, so
// each loop visits each node and each edge at most once.
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

#include <cstddef>
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

// The least set holding the seeds and closed under the gated graph's
// clauses: a plain edge from a marked node marks its target; a guarded
// edge does once its source and its guard are both marked. A node that
// rises fires its plain edges, its guarded edges whose guard has risen,
// and, as a guard, the edges it guards whose source has risen: every
// clause is met by whichever of its two premises rises last.
template <class Tag>
BitSet<Id<Tag>> mark(const GatedCsr<Tag> &g, std::span<const Id<Tag>> seeds) {
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
    for (Node next : g.plain(node))
      rise(next);
    IdRange<Node> targets = g.guardedTargets(node), guards = g.guards(node);
    for (std::size_t e = 0; e < targets.size(); ++e)
      if (marked.test(guards[e]))
        rise(targets[e]);
    IdRange<Node> sources = g.waitingSources(node), guarded = g.waitingTargets(node);
    for (std::size_t e = 0; e < sources.size(); ++e)
      if (marked.test(sources[e]))
        rise(guarded[e]);
  }
  return marked;
}

} // namespace idr

#endif // IDR_ANALYSIS_SOLVER_MARK_H
