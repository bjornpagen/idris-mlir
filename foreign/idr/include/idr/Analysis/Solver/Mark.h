// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The marking: every node reachable from the seeds, in one direction, a
// node that rises walking its row once. Its four clients (exclusivity,
// allocation into a lifetime, borrows, the obligation closure) share the
// two loops of Mark.cpp, ordinary functions compiled once for every graph:
// the tag is shed at the call and the answer wrapped again, so N graph
// types make no N copies of a loop.
//
// A marking cannot fail and cannot stop early: its answer is a set that
// only rises, every node rises at most once, and the loop ends when the
// worklist is empty. A solve unit of one is traced, never skipped (Trace.h).
#ifndef IDR_ANALYSIS_SOLVER_MARK_H
#define IDR_ANALYSIS_SOLVER_MARK_H

#include "idr/Analysis/Solver/Graph.h"
#include "idr/Support/Id.h"

#include "llvm/ADT/BitVector.h"

#include <cstdint>
#include <span>
#include <utility>
#include <vector>

namespace idr {

namespace detail {
// The nodes reachable from `seeds` along `rows`, seeds included.
llvm::BitVector markRows(Rows rows, std::uint32_t count, std::span<const std::uint32_t> seeds);
// The least set holding the seeds and closed under the gated graph's
// clauses: a plain edge from a marked node marks its target; a guarded
// edge does once its source and its guard are both marked.
llvm::BitVector markGated(const GatedRows &rows, std::uint32_t count,
                          std::span<const std::uint32_t> seeds);

// A set of ids from the marking's bits: the one place a marking's answer
// becomes typed, sized by the minter's own count.
template <class IdT>
BitSet<IdT> rewrap(Count<IdT> count, llvm::BitVector bits) {
  return BitSet<IdT>(count, std::move(bits));
}

// The seeds' raw numbers: an Id is its number, read through index().
template <class IdT>
std::vector<std::uint32_t> raw(std::span<const IdT> seeds) {
  std::vector<std::uint32_t> out;
  out.reserve(seeds.size());
  for (IdT seed : seeds)
    out.push_back(seed.index());
  return out;
}
} // namespace detail

template <Direction D, class Tag>
BitSet<Id<Tag>> mark(const Csr<Tag> &g, std::span<const Id<Tag>> seeds) {
  return detail::rewrap(g.size(),
                        detail::markRows(g.rows(D{}), g.size().value(), detail::raw(seeds)));
}

template <class Tag>
BitSet<Id<Tag>> mark(const GatedCsr<Tag> &g, std::span<const Id<Tag>> seeds) {
  return detail::rewrap(g.size(),
                        detail::markGated(g.rows(), g.size().value(), detail::raw(seeds)));
}

} // namespace idr

#endif // IDR_ANALYSIS_SOLVER_MARK_H
