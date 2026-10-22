// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Summaries over the program graph's components: the solve shape of every
// per-function fact a caller reads (an effect row, a lifetime signature, a
// binding time) or a callee reads (a dead result). Each component runs on
// the one static schedule (Schedule.h), after the components it reads,
// callees first or callers first; inside a component its members are
// solved together to their least fixpoint.
//
// A problem's local facts (a function's own ops, projected) are extracted
// per function before the solve and held by the problem, so the solve
// names no MLIR: `transfer` joins them with its neighbours' summaries. It
// is const and reads only finished components and its own component's
// members, which its own task alone writes, so components run in parallel
// with no lock, and the answer is the unique least fixpoint whatever the
// schedule: byte-identical at any thread count.
//
// Each problem compiles the solve once: its header declares the
// instantiation `extern template`, and one unit includes SummarizeImpl.h
// and instantiates it. No other unit compiles the loop.
#ifndef IDR_ANALYSIS_SOLVER_SUMMARIZE_H
#define IDR_ANALYSIS_SOLVER_SUMMARIZE_H

#include "idr/Analysis/Solver/Lattice.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/Support/Id.h"

#include "mlir/IR/MLIRContext.h"

#include <concepts>

namespace idr::solver {

template <class P>
concept SummaryProblem = requires(const P &p, const ProgramGraph &g, FunctionId f,
                                  const IndexVector<FunctionId, typename P::Summary> &done) {
  requires NodeState<typename P::Summary>;
  requires Policy<typename P::Policy>;
  requires (std::same_as<typename P::Policy, Exact> && FiniteHeight<typename P::Summary>) ||
               (std::same_as<typename P::Policy, Budgeted> && Bounded<typename P::Summary> &&
                requires { { p.budget } -> std::convertible_to<Budgeted>; });
  { p.transfer(g, f, done) } -> std::same_as<typename P::Summary>;
};

// Every function's summary, each component solved after the components it
// reads: its callees' (CalleesFirst) or its callers' (CallersFirst). The
// transfers it makes are added to `work`.
template <Order O, SummaryProblem P>
IndexVector<FunctionId, typename P::Summary> summarize(const ProgramGraph &g, const P &problem,
                                                       mlir::MLIRContext &context, Work &work);

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_SUMMARIZE_H
