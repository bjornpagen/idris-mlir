// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The definition of the summary solve. Included by exactly one unit per
// problem, the one that instantiates it; no header includes it.
#ifndef IDR_ANALYSIS_SOLVER_SUMMARIZEIMPL_H
#define IDR_ANALYSIS_SOLVER_SUMMARIZEIMPL_H

#include "idr/Analysis/Solver/Summarize.h"
#include "idr/Analysis/Solver/Trace.h"

#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/ThreadPool.h"

#include <algorithm>
#include <atomic>
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

// One component's members to their least fixpoint, from bottom, given every
// component it reads finished. A component of one function that does not
// call itself takes one transfer; any other iterates until no member rises,
// which the lattice's height ends (Exact), or until its budget is spent,
// when every member is written top, which every value lies below
// (Budgeted).
template <SummaryProblem P>
Changed round(const ProgramGraph &g, const P &problem, IdRange<FunctionId> members,
              IndexVector<FunctionId, typename P::Summary> &done) {
  Changed rose = Changed::No;
  for (FunctionId f : members)
    if (done[f].join(problem.transfer(g, f, done)) == Changed::Yes)
      rose = Changed::Yes;
  return rose;
}

template <SummaryProblem P>
void solveComponent(const ProgramGraph &g, const P &problem, SccId c,
                    IndexVector<FunctionId, typename P::Summary> &done) {
  using S = typename P::Summary;
  IdRange<FunctionId> members = g.members(c);
  for (FunctionId f : members)
    done[f] = S::bottom();
  if (members.size() == 1 && !g.callsItself(members.front())) {
    (void)round(g, problem, members, done);
    return;
  }
  if constexpr (std::same_as<typename P::Policy, Exact>) {
    while (round(g, problem, members, done) == Changed::Yes) {
    }
  } else {
    std::uint64_t allowed = std::uint64_t(Budgeted(problem.budget).perMember);
    for (std::uint64_t spent = 0; round(g, problem, members, done) == Changed::Yes;) {
      if (++spent < allowed)
        continue;
      for (FunctionId f : members)
        done[f] = S::top();
      return;
    }
  }
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

template <Order O, SummaryProblem P>
IndexVector<FunctionId, typename P::Summary> summarize(const ProgramGraph &g, const P &problem,
                                                       mlir::MLIRContext &context) {
  using S = typename P::Summary;
  IndexVector<FunctionId, S> done = g.table(S::bottom());
  std::vector<SccId> sccs = detail::scheduled<O>(g);
  auto n = static_cast<std::uint32_t>(sccs.size());

  // Serial in the schedule's order when the context runs on one thread.
  if (!context.isMultithreadingEnabled()) {
    for (SccId c : sccs) {
      SolveUnit unit("summarize", g.op(g.members(c).front()).getSymName());
      detail::solveComponent(g, problem, c, done);
    }
    return done;
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
    const ProgramGraph &g;
    const P &problem;
    IndexVector<FunctionId, S> &done;
    const std::vector<SccId> &sccs;
    const std::vector<std::vector<std::uint32_t>> &waiters;
    std::atomic<std::uint32_t> *waiting;
    llvm::ThreadPoolTaskGroup &group;

    void operator()(std::uint32_t at) const {
      SccId c = sccs[at];
      {
        SolveUnit unit("summarize", g.op(g.members(c).front()).getSymName());
        detail::solveComponent(g, problem, c, done);
      }
      for (std::uint32_t next : waiters[at])
        if (waiting[next].fetch_sub(1, std::memory_order_acq_rel) == 1)
          group.async([task = *this, next] { task(next); });
    }
  };
  Task task{g, problem, done, sccs, waiters, waiting.get(), group};
  for (std::uint32_t at = 0; at < n; ++at)
    if (waiting[at].load(std::memory_order_relaxed) == 0)
      group.async([task, at] { task(at); });
  group.wait();
  return done;
}

template <Order O, SummaryProblem P>
void resummarize(const ProgramGraph &g, const P &problem,
                 IndexVector<FunctionId, typename P::Summary> &done,
                 std::span<const FunctionId> seeds) {
  using S = typename P::Summary;
  llvm::BitVector dirty(g.sccCount().value());
  for (FunctionId seed : seeds)
    dirty.set(g.sccOf(seed).index());
  for (SccId c : detail::scheduled<O>(g)) {
    if (!dirty.test(c.index()))
      continue;
    std::vector<S> before;
    for (FunctionId f : g.members(c))
      before.push_back(done[f]);
    {
      SolveUnit unit("resummarize", g.op(g.members(c).front()).getSymName());
      detail::solveComponent(g, problem, c, done);
    }
    bool same = llvm::all_of(llvm::zip_equal(g.members(c), before),
                             [&](auto pair) { return done[std::get<0>(pair)] == std::get<1>(pair); });
    if (same)
      continue;
    // The components that read this one, in the schedule's direction.
    for (FunctionId f : g.members(c)) {
      if constexpr (std::same_as<O, CalleesFirst>) {
        for (FunctionId caller : g.callers(f))
          dirty.set(g.sccOf(caller).index());
      } else {
        for (const Call &call : g.callees(f))
          dirty.set(g.sccOf(call.callee).index());
      }
    }
  }
}

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_SUMMARIZEIMPL_H
