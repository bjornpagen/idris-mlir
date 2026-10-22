// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one writer of rows, and idr-constants.
//
// A function's row is the least solution of: its own part (the
// derivation's fold of its body), joined with the row of each function it
// calls. Over the program graph's components, callees first, one pass is
// exact: every member of a component reaches every other through calls,
// so its members share one row, the join of their own parts and of the
// rows of the components they call. A cycle of ours may run forever unless
// Idris proved every function on it in one and the same component of its
// own; that is the cycle's, not any one function's, so the writer adds it
// and no function's check can. The record follows the same way: a write
// through a parameter passed on to a callee's written parameter is a write
// through the caller's; what a callee puts into a lifetime passed on is
// put into the caller's, with no bound where the call lies on a cycle or
// in a region that runs again.
//
// Rows are equal to their derivation right after the writer, and cover it
// after every other pass. The writer runs where effects change: in
// defunctionalization's decision (atoms alone, over the label solve's
// reading of each label's run), after each of the optimizer's components,
// at the end of every program pass that adds effects, and last before the
// lowering. A nested pass that adds effects runs after `widen`, which
// gives every function and call at least the atoms it may add.
//
// idr-constants is the last step of idr-optimize's inner pipeline: one
// function's constants, its calls' results taken from their callees'
// summaries in the optimizer's schedule.
#ifndef IDR_TRANSFORMS_EFFECTS_H
#define IDR_TRANSFORMS_EFFECTS_H

#include "idr/Analysis/Effects.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Summarize.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"

#include "mlir/IR/Threading.h"
#include "mlir/Pass/Pass.h"

#include <memory>
#include <span>

namespace idr::rows {

// Every function's row and record, and every call's copy, equal to their
// derivation: what each changed is written, nothing else. Reads each body
// in parallel, joins over `graph`'s components serially, writes each
// function and its calls in parallel. Every attribute a record needs is
// made serially, before the parallel writes.
void write(ProgramOp program, const solver::ProgramGraph &graph);

// Every function and call holds at least `atoms` besides its own, and no
// parameter is known untouched: what a nested pass that adds effects runs
// after, so its own functions' checks hold while it runs. The writer
// narrows them again.
void widen(ProgramOp program, effects::Row atoms);

// One component's members, when the optimizer finishes the component:
// every callee outside it is final, and each call of one holds the
// callee's row already (the optimizer writes a caller's calls when its turn
// begins, copyCallee), so the members' rows read only their own bodies.
// `names` resolves a callee to its id: the frozen graph, or the editor the
// optimizer holds.
template <solver::FunctionNames N>
void writeComponent(std::span<const solver::Member> members, const N &names);

extern template void writeComponent<solver::ProgramGraph>(std::span<const solver::Member>,
                                                          const solver::ProgramGraph &);
extern template void writeComponent<solver::Editor>(std::span<const solver::Member>,
                                                    const solver::Editor &);

// The atoms alone, a function's own part joined callees first: the
// summary problem over the program graph, compiled once (Writer.cpp).
struct AtomsProblem {
  using Summary = effects::Row;
  using Policy = Exact;

  // Each function's own part, the cycle's divergence included.
  IndexVector<solver::FunctionId, effects::Row> own;

  effects::Row transfer(const solver::ProgramGraph &graph, solver::FunctionId f,
                        const IndexVector<solver::FunctionId, effects::Row> &done) const {
    effects::Row row = own[f];
    for (const solver::Call &call : graph.callees(f))
      row = row | done[call.callee];
    return row;
  }
};

namespace detail {
// The divergence of each cycle no single proof of Idris's covers, joined
// into each member's own part.
void addCycles(const solver::ProgramGraph &graph, IndexVector<solver::FunctionId, effects::Row> &own);
} // namespace detail

} // namespace idr::rows

namespace idr::solver {
extern template IndexVector<FunctionId, effects::Row>
summarize<CalleesFirst, rows::AtomsProblem>(const ProgramGraph &, const rows::AtomsProblem &,
                                           mlir::MLIRContext &);
} // namespace idr::solver

namespace idr::rows {

// Every function's atoms, each body read by its own copy of `reader`: what
// defunctionalization's decision asks before it converts, its reader
// reading each label's run as calls of the labels the label solve gives
// it, and `graph` holding those runs as calls. Before counting no
// parameter admits a part, so the atoms are the whole row.
template <CallReader R>
IndexVector<solver::FunctionId, effects::Row> solveAtoms(const solver::ProgramGraph &graph,
                                                       const R &reader,
                                                       mlir::MLIRContext &context) {
  AtomsProblem problem{graph.table(effects::Row{})};
  IdRange<solver::FunctionId> functions = graph.functions();
  mlir::parallelFor(&context, 0, functions.size(), [&](std::size_t at) {
    solver::FunctionId f = functions[at];
    R mine = reader;
    problem.own[f] = derive(graph.op(f), mine).atoms;
  });
  detail::addCycles(graph, problem.own);
  return solver::summarize<CalleesFirst>(graph, problem, context);
}

} // namespace idr::rows

namespace idr::optimize {

class Schedule;

// The step for one run of idr-optimize: it reads the summaries of the
// functions `schedule` holds final, and counts the values it replaces into
// `constants`.
std::unique_ptr<mlir::Pass> createConstants(const Schedule &schedule,
                                            mlir::Pass::Statistic &constants);

} // namespace idr::optimize

#endif // IDR_TRANSFORMS_EFFECTS_H
