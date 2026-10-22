// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The layout of compressed rows, compiled once for every graph of ours.
#include "idr/Analysis/Solver/Graph.h"

#include <numeric>

namespace idr::detail {

void layOut(std::uint32_t rows, std::span<const std::pair<std::uint32_t, std::uint32_t>> edges,
            Root root, footprint::Vector<std::uint32_t> &start,
            footprint::Vector<std::uint32_t> &to) {
  std::uint32_t extra = root == Root::Present ? 1 : 0;
  start.assign(rows + extra + 1, 0);
  for (auto [from, target] : edges)
    ++start[from + 1];
  if (root == Root::Present)
    start[rows + 1] = rows;
  std::partial_sum(start.begin(), start.end(), start.begin());
  to.resize(start.back());
  // Each row filled in the order its edges came, from a cursor per row.
  footprint::Vector<std::uint32_t> cursor(start.begin(), start.end() - 1);
  for (auto [from, target] : edges)
    to[cursor[from]++] = target;
  if (root == Root::Present)
    std::iota(to.begin() + start[rows], to.end(), 0u);
}

void layOutGuarded(std::uint32_t rows, std::span<const GuardedEdge> edges,
                   footprint::Vector<std::uint32_t> &byFromStart,
                   footprint::Vector<std::uint32_t> &byFromTo,
                   footprint::Vector<std::uint32_t> &byFromGuard,
                   footprint::Vector<std::uint32_t> &byGuardStart,
                   footprint::Vector<std::uint32_t> &byGuardFrom,
                   footprint::Vector<std::uint32_t> &byGuardTo) {
  byFromStart.assign(rows + 1, 0);
  byGuardStart.assign(rows + 1, 0);
  for (const GuardedEdge &edge : edges) {
    ++byFromStart[edge.from + 1];
    ++byGuardStart[edge.guard + 1];
  }
  std::partial_sum(byFromStart.begin(), byFromStart.end(), byFromStart.begin());
  std::partial_sum(byGuardStart.begin(), byGuardStart.end(), byGuardStart.begin());
  byFromTo.resize(edges.size());
  byFromGuard.resize(edges.size());
  byGuardFrom.resize(edges.size());
  byGuardTo.resize(edges.size());
  footprint::Vector<std::uint32_t> fromCursor(byFromStart.begin(), byFromStart.end() - 1);
  footprint::Vector<std::uint32_t> guardCursor(byGuardStart.begin(), byGuardStart.end() - 1);
  for (const GuardedEdge &edge : edges) {
    std::uint32_t byFrom = fromCursor[edge.from]++;
    byFromTo[byFrom] = edge.to;
    byFromGuard[byFrom] = edge.guard;
    std::uint32_t byGuard = guardCursor[edge.guard]++;
    byGuardFrom[byGuard] = edge.from;
    byGuardTo[byGuard] = edge.to;
  }
}

} // namespace idr::detail
