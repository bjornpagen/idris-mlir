// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The two marking loops, a worklist each; no recursion and no map. A node
// is pushed only when it rises, and it rises once, so each loop visits each
// node and each edge at most once.
#include "idr/Analysis/Solver/Mark.h"

#include <vector>

namespace idr::detail {

llvm::BitVector markRows(Rows rows, std::uint32_t count, std::span<const std::uint32_t> seeds) {
  llvm::BitVector marked(count);
  std::vector<std::uint32_t> work;
  auto rise = [&](std::uint32_t node) {
    if (marked.test(node))
      return;
    marked.set(node);
    work.push_back(node);
  };
  for (std::uint32_t seed : seeds)
    rise(seed);
  while (!work.empty()) {
    std::uint32_t node = work.back();
    work.pop_back();
    for (std::uint32_t next : rows.row(node))
      rise(next);
  }
  return marked;
}

// A node that rises fires its plain edges, its guarded edges whose guard
// has risen, and, as a guard, the edges waiting on it whose source has
// risen. Every clause is met by whichever of its two premises rises last.
llvm::BitVector markGated(const GatedRows &rows, std::uint32_t count,
                          std::span<const std::uint32_t> seeds) {
  llvm::BitVector marked(count);
  std::vector<std::uint32_t> work;
  auto rise = [&](std::uint32_t node) {
    if (marked.test(node))
      return;
    marked.set(node);
    work.push_back(node);
  };
  for (std::uint32_t seed : seeds)
    rise(seed);
  while (!work.empty()) {
    std::uint32_t node = work.back();
    work.pop_back();
    for (std::uint32_t next : rows.plain.row(node))
      rise(next);
    for (std::uint32_t e = rows.guardedStart[node]; e < rows.guardedStart[node + 1]; ++e)
      if (marked.test(rows.guarded[e].guard))
        rise(rows.guarded[e].to);
    for (std::uint32_t e = rows.waitingStart[node]; e < rows.waitingStart[node + 1]; ++e)
      if (marked.test(rows.waiting[e].from))
        rise(rows.waiting[e].to);
  }
  return marked;
}

} // namespace idr::detail
