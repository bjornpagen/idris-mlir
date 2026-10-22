// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The definition of the summary solve. Included by exactly one unit per
// problem, the one that instantiates it; no header includes it.
#ifndef IDR_ANALYSIS_SOLVER_SUMMARIZEIMPL_H
#define IDR_ANALYSIS_SOLVER_SUMMARIZEIMPL_H

#include "idr/Analysis/Solver/Schedule.h"
#include "idr/Analysis/Solver/Summarize.h"
#include "idr/Analysis/Solver/Trace.h"

#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

#include <cstdint>
#include <vector>

namespace idr::solver {

namespace detail {

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

} // namespace detail

// Each component on the one static schedule, its members written by its
// own task alone.
template <Order O, SummaryProblem P>
IndexVector<FunctionId, typename P::Summary> summarize(const ProgramGraph &g, const P &problem,
                                                       mlir::MLIRContext &context) {
  using S = typename P::Summary;
  IndexVector<FunctionId, S> done = g.table(S::bottom());
  inSchedule<O>(g, context, [&](SccId c) {
    SolveUnit unit("summarize", g.op(g.members(c).front()).getSymName());
    detail::solveComponent(g, problem, c, done);
  });
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
