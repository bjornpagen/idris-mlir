// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The layout of compressed rows, compiled once for every graph of ours.
#include "idr/Analysis/Solver/Graph.h"

#include <numeric>

namespace idr::detail {

void layOut(std::uint32_t rows, std::span<const std::pair<std::uint32_t, std::uint32_t>> edges,
            Root root, std::vector<std::uint32_t> &start, std::vector<std::uint32_t> &to) {
  std::uint32_t extra = root == Root::Present ? 1 : 0;
  start.assign(rows + extra + 1, 0);
  for (auto [from, target] : edges)
    ++start[from + 1];
  if (root == Root::Present)
    start[rows + 1] = rows;
  std::partial_sum(start.begin(), start.end(), start.begin());
  to.resize(start.back());
  // Each row filled in the order its edges came, from a cursor per row.
  std::vector<std::uint32_t> cursor(start.begin(), start.end() - 1);
  for (auto [from, target] : edges)
    to[cursor[from]++] = target;
  if (root == Root::Present)
    std::iota(to.begin() + start[rows], to.end(), 0u);
}

void layOutGuarded(std::uint32_t rows, std::span<const std::uint32_t> from,
                   std::span<const Guarded> edges, std::vector<std::uint32_t> &byFromStart,
                   std::vector<Guarded> &byFrom, std::vector<std::uint32_t> &byGuardStart,
                   std::vector<Waiting> &byGuard) {
  byFromStart.assign(rows + 1, 0);
  byGuardStart.assign(rows + 1, 0);
  for (std::size_t e = 0; e < edges.size(); ++e) {
    ++byFromStart[from[e] + 1];
    ++byGuardStart[edges[e].guard + 1];
  }
  std::partial_sum(byFromStart.begin(), byFromStart.end(), byFromStart.begin());
  std::partial_sum(byGuardStart.begin(), byGuardStart.end(), byGuardStart.begin());
  byFrom.resize(edges.size());
  byGuard.resize(edges.size());
  std::vector<std::uint32_t> fromCursor(byFromStart.begin(), byFromStart.end() - 1);
  std::vector<std::uint32_t> guardCursor(byGuardStart.begin(), byGuardStart.end() - 1);
  for (std::size_t e = 0; e < edges.size(); ++e) {
    byFrom[fromCursor[from[e]]++] = edges[e];
    byGuard[guardCursor[edges[e].guard]++] = {from[e], edges[e].to};
  }
}

} // namespace idr::detail
