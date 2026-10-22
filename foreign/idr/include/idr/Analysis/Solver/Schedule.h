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
// writes: byte-identical at any thread count.
#ifndef IDR_ANALYSIS_SOLVER_SCHEDULE_H
#define IDR_ANALYSIS_SOLVER_SCHEDULE_H

#include "idr/Analysis/Solver/Lattice.h"
#include "idr/Analysis/Solver/ProgramGraph.h"

#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ThreadPool.h"

#include <algorithm>
#include <atomic>
#include <concepts>
#include <cstdint>
#include <memory>
#include <vector>

namespace idr::solver {

namespace detail {

// The components a component reads, in the schedule's direction: those of
// its members' callees, or of its members' callers; never itself.
template <Order O>
std::vector<std::uint32_t> reads(const ProgramGraph &g, SccId c) {
  std::vector<std::uint32_t> out;
  for (FunctionId f : g.members(c)) {
    if constexpr (std::same_as<O, CalleesFirst>) {
      for (const Call &call : g.callees(f))
        out.push_back(g.sccOf(call.callee).index());
    } else {
      for (FunctionId caller : g.callers(f))
        out.push_back(g.sccOf(caller).index());
    }
  }
  llvm::sort(out);
  out.erase(std::unique(out.begin(), out.end()), out.end());
  llvm::erase(out, c.index());
  return out;
}

// Every component in the schedule's order: ids ascending callees first,
// descending callers first.
template <Order O>
std::vector<SccId> scheduled(const ProgramGraph &g) {
  std::vector<SccId> out;
  out.reserve(g.sccCount().value());
  for (SccId c : g.sccCount().ids())
    out.push_back(c);
  if constexpr (std::same_as<O, CallersFirst>)
    std::reverse(out.begin(), out.end());
  return out;
}

} // namespace detail

// Runs `solve` on every component of `g`, each after every component it
// reads: serially in the schedule's order when the context runs on one
// thread, else as tasks on the context's pool. Returns when every
// component has run.
template <Order O, class Solve>
  requires std::invocable<const Solve &, SccId>
void inSchedule(const ProgramGraph &g, mlir::MLIRContext &context, const Solve &solve) {
  std::vector<SccId> sccs = detail::scheduled<O>(g);
  auto n = static_cast<std::uint32_t>(sccs.size());
  if (!context.isMultithreadingEnabled()) {
    for (SccId c : sccs)
      solve(c);
    return;
  }

  // Each component waits on the components it reads; a finished one
  // releases each component waiting on it, and the last release submits it.
  // Indexed by component id: a component's position in `sccs` is its id
  // callees first, and n - 1 - its id callers first.
  auto position = [&](std::uint32_t id) {
    if constexpr (std::same_as<O, CalleesFirst>)
      return id;
    else
      return n - 1 - id;
  };
  std::vector<std::vector<std::uint32_t>> waiters(n);
  std::unique_ptr<std::atomic<std::uint32_t>[]> waiting(new std::atomic<std::uint32_t>[n]);
  for (std::uint32_t at = 0; at < n; ++at) {
    std::vector<std::uint32_t> on = detail::reads<O>(g, sccs[at]);
    waiting[at].store(static_cast<std::uint32_t>(on.size()), std::memory_order_relaxed);
    for (std::uint32_t d : on)
      waiters[position(d)].push_back(at);
  }

  llvm::ThreadPoolTaskGroup group(context.getThreadPool());
  struct Task {
    const Solve &solve;
    const std::vector<SccId> &sccs;
    const std::vector<std::vector<std::uint32_t>> &waiters;
    std::atomic<std::uint32_t> *waiting;
    llvm::ThreadPoolTaskGroup &group;

    void operator()(std::uint32_t at) const {
      solve(sccs[at]);
      for (std::uint32_t next : waiters[at])
        if (waiting[next].fetch_sub(1, std::memory_order_acq_rel) == 1)
          group.async([task = *this, next] { task(next); });
    }
  };
  Task task{solve, sccs, waiters, waiting.get(), group};
  for (std::uint32_t at = 0; at < n; ++at)
    if (waiting[at].load(std::memory_order_relaxed) == 0)
      group.async([task, at] { task(at); });
  group.wait();
}

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_SCHEDULE_H
