// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The definition of the summary solve. Included by exactly one unit per
// problem, the one that instantiates it; no header includes it.
#ifndef IDR_ANALYSIS_SOLVER_SUMMARIZEIMPL_H
#define IDR_ANALYSIS_SOLVER_SUMMARIZEIMPL_H

#include "idr/Analysis/Solver/Schedule.h"
#include "idr/Analysis/Solver/Summarize.h"
#include "idr/Analysis/Solver/Trace.h"

#include <cstdint>

namespace idr::solver {

namespace detail {

// One round over a component's members: a transfer of each.
template <SummaryProblem P>
Changed round(const ProgramGraph &g, const P &problem, IdRange<FunctionId> members,
              IndexVector<FunctionId, typename P::Summary> &done) {
  Changed rose = Changed::No;
  for (FunctionId f : members)
    if (done[f].join(problem.transfer(g, f, done)) == Changed::Yes)
      rose = Changed::Yes;
  return rose;
}

// One component's members to their least fixpoint, from bottom, given every
// component it reads finished; the transfers it made. A component of one
// function that does not call itself takes one transfer; any other iterates
// until no member rises, which the lattice's height ends (Exact), or until
// its budget is spent, when every member is written top, which every value
// lies below (Budgeted).
template <SummaryProblem P>
std::uint64_t solveComponent(const ProgramGraph &g, const P &problem, SccId c,
                             IndexVector<FunctionId, typename P::Summary> &done) {
  using S = typename P::Summary;
  IdRange<FunctionId> members = g.members(c);
  for (FunctionId f : members)
    done[f] = S::bottom();
  if (members.size() == 1 && !g.callsItself(members.front())) {
    (void)round(g, problem, members, done);
    return 1;
  }
  std::uint64_t rounds = 1;
  if constexpr (std::same_as<typename P::Policy, Exact>) {
    for (; round(g, problem, members, done) == Changed::Yes; ++rounds) {
    }
  } else {
    std::uint64_t allowed = std::uint64_t(Budgeted(problem.budget).perMember);
    for (std::uint64_t spent = 0; round(g, problem, members, done) == Changed::Yes; ++rounds) {
      if (++spent < allowed)
        continue;
      for (FunctionId f : members)
        done[f] = S::top();
      break;
    }
  }
  return rounds * members.size();
}

} // namespace detail

// Each component on the one static schedule, its members written by its
// own task alone, and its transfers added once it is solved.
template <Order O, SummaryProblem P>
IndexVector<FunctionId, typename P::Summary> summarize(const ProgramGraph &g, const P &problem,
                                                       mlir::MLIRContext &context, Work &work) {
  using S = typename P::Summary;
  IndexVector<FunctionId, S> done = g.table(S::bottom());
  inSchedule<O>(g, context, [&](SccId c) {
    SolveUnit unit("summarize", g.op(g.members(c).front()).getSymName());
    work.add(detail::solveComponent(g, problem, c, done));
  });
  return done;
}

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_SUMMARIZEIMPL_H
