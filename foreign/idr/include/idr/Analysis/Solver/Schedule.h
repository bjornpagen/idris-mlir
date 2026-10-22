// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one static schedule of a solve over the program graph's components:
// a component starts when the last component it reads finishes, callees
// first or callers first, as dependency-count tasks on the context's pool
// with no barrier. Every solve over components runs on it: the summaries
// (Summarize.h) and the solves whose units are too dear to transfer again
// (Ranges, one dataflow solve per function).
//
// A solve on it writes only its own component's entries and reads only
// finished components' and its own: a component's task alone writes its
// members, and the release of a finished component orders its writes
// before every task that reads them. So components run in parallel with no
// lock, and what each writes is what a serial run in the schedule's order
// writes: byte-identical at any thread count. Its tables, indexed by
// component, are the footprint's.
#ifndef IDR_ANALYSIS_SOLVER_SCHEDULE_H
#define IDR_ANALYSIS_SOLVER_SCHEDULE_H

#include "idr/Analysis/Solver/Lattice.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ThreadPool.h"

#include <algorithm>
#include <atomic>
#include <concepts>
#include <cstdint>
#include <ranges>
#include <type_traits>

namespace idr::solver {

namespace detail {

// The other order: a component's readers in one order are what it reads in
// the other.
template <Order O>
using Reversed = std::conditional_t<std::same_as<O, CalleesFirst>, CallersFirst, CalleesFirst>;

// The components a component reads, in the schedule's direction: those of
// its members' callees, or of its members' callers; never itself.
template <Order O>
footprint::Vector<SccId> reads(const ProgramGraph &g, SccId c) {
  footprint::Vector<SccId> out;
  for (FunctionId f : g.members(c)) {
    if constexpr (std::same_as<O, CalleesFirst>) {
      for (const Call &call : g.callees(f))
        out.push_back(g.sccOf(call.callee));
    } else {
      for (FunctionId caller : g.callers(f))
        out.push_back(g.sccOf(caller));
    }
  }
  llvm::sort(out);
  out.erase(std::unique(out.begin(), out.end()), out.end());
  llvm::erase(out, c);
  return out;
}

// Every component in the schedule's order: ids ascending callees first,
// descending callers first.
template <Order O, class Visit>
void inOrder(const ProgramGraph &g, Visit &&visit) {
  auto ids = g.sccCount().ids();
  if constexpr (std::same_as<O, CalleesFirst>) {
    for (SccId c : ids)
      visit(c);
  } else {
    for (SccId c : std::views::reverse(ids))
      visit(c);
  }
}

} // namespace detail

// Runs `solve` on every component of `g`, each after every component it
// reads: serially in the schedule's order when the context runs on one
// thread, else as tasks on the context's pool. Returns when every
// component has run.
template <Order O, class Solve>
  requires std::invocable<const Solve &, SccId>
void inSchedule(const ProgramGraph &g, mlir::MLIRContext &context, const Solve &solve) {
  if (!context.isMultithreadingEnabled()) {
    detail::inOrder<O>(g, [&](SccId c) { solve(c); });
    return;
  }

  // Each component waits on the components it reads, and is waited on by
  // those that read it, which are what it reads in the other order; a
  // finished one releases each component waiting on it, and the last
  // release submits it.
  Count<SccId> sccs = g.sccCount();
  IndexVector<SccId, std::atomic<std::uint32_t>> waiting(sccs);
  for (SccId c : sccs.ids())
    waiting[c].store(static_cast<std::uint32_t>(detail::reads<O>(g, c).size()),
                     std::memory_order_relaxed);
  Ragged<SccId, SccId> waiters(
      sccs, [&](SccId c) { return detail::reads<detail::Reversed<O>>(g, c); });

  llvm::ThreadPoolTaskGroup group(context.getThreadPool());
  struct Task {
    const Solve &solve;
    const Ragged<SccId, SccId> &waiters;
    IndexVector<SccId, std::atomic<std::uint32_t>> &waiting;
    llvm::ThreadPoolTaskGroup &group;

    void operator()(SccId c) const {
      solve(c);
      for (SccId next : waiters[c])
        if (waiting[next].fetch_sub(1, std::memory_order_acq_rel) == 1)
          group.async([task = *this, next] { task(next); });
    }
  };
  Task task{solve, waiters, waiting, group};
  detail::inOrder<O>(g, [&](SccId c) {
    if (waiting[c].load(std::memory_order_relaxed) == 0)
      group.async([task, c] { task(c); });
  });
  group.wait();
}

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_SCHEDULE_H
