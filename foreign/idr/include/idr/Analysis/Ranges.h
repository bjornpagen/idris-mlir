// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ranges of the program's integers, bigs and naturals: MLIR's integer
// range analysis on one function at a time, a value it cannot see computed
// starting at the range its type proves, joined across calls by summaries
// over the program graph's components: what each function returns, callees
// first, and what each is passed, callers first, each on the solver
// layer's static schedule, so independent components are solved at once.
// The solve that learns what a function passes is its solve under the final
// summaries, its arguments starting at their summary and each call's
// results at its callee's: the bounds of every value of the function are
// read off it there, once, and kept, so idr-narrow decides them and each
// function idr-narrow-words versions and narrows reads its own.
//
// The state of a solve is one function's values, gone once the solve is
// read; the summaries are a range per parameter and per result, and what
// each function passes each callee of another component, which the
// callee's component joins when it starts; the bounds are one per value of
// the program, in each function's walk order. Inside a component of two
// functions or more, or of one that calls itself, a summary that would
// feed itself is its type's whole range, as upstream's analysis widens a
// value a loop keeps changing: a wider range is still a range of the
// value, and every reader takes a range as a bound to narrow or version
// under. Nothing refuses or errors on a range. Each component writes its
// own members' summaries alone, in its members' order, and joins only
// finished components', so the summaries are the same bytes at any thread
// count.
//
// A solve's work is the transfers the range analysis makes over the
// function: each op, call and region entry it visits, each time it visits
// one. The summaries are rows of one footprint table per side, a range per
// position, and the bounds a row per function; a function's solve is
// upstream's dataflow state, outside them.
#ifndef IDR_ANALYSIS_RANGES_H
#define IDR_ANALYSIS_RANGES_H

#include "idr/Analysis/Solver/Decision.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Support/TypeID.h"

#include <concepts>
#include <optional>
#include <span>

namespace idr {

class Ranges : public solver::ReadsAnalyses<Ranges, solver::ProgramGraph> {
public:
  static constexpr llvm::StringLiteral decideStep = "idr-narrow";

  // The summaries of `program`, an idr.program: its program graph's
  // components callees first for returns, then callers first for
  // arguments, each function solved alone, and the bounds of each
  // function's values read off its solve under the final summaries.
  Ranges(mlir::Operation *program, mlir::AnalysisManager &am);

  // The bounds of every value of `fn` in the one walk order
  // (solver::inWalkOrder), as its solve under the final summaries found
  // them, for `fn` as that solve saw it.
  std::span<const ranges::Bounds> boundsOf(idr::FuncOp fn) const {
    return bounded[graph.id(fn)];
  }

  // The bounds of every value of `fn` in the one walk order, solved again
  // under the summaries, its transfers added to `work`: for `fn` rewritten
  // since they were decided, by a rewrite under which they still hold,
  // which passes each callee and returns nothing the values it replaced
  // did not (a loop versioned, whose two copies start inside what the
  // loop started from). Its values are new, so no solve saw them.
  footprint::Vector<ranges::Bounds> boundsOfRewritten(idr::FuncOp fn, solver::Work &work) const;

  // The one read of an integer range lattice, of this solver or of any
  // other that ran MLIR's integer range analysis.
  static std::optional<mlir::ConstantIntRanges> rangeOf(const mlir::DataFlowSolver &solver,
                                                        mlir::Value value);

  // What a call of the function a call names returns, by result,
  // uninitialized where nothing reached it.
  std::span<const mlir::IntegerValueRange> returnsOf(mlir::FlatSymbolRefAttr callee) const {
    return returns[graph.id(callee)];
  }

  // The transfers the summaries' solves made, the decide step's work.
  std::uint64_t work() const { return spent.steps(); }

private:
  // Solves `fn` under the summaries, adds its transfers to `work`, and
  // hands the solve to `read` while it lives. MLIR's solver fails only
  // where an analysis it runs does, which none of these does on any input:
  // a failure is an internal error.
  template <class Read>
    requires std::invocable<Read &, const mlir::DataFlowSolver &>
  void solve(idr::FuncOp fn, solver::Work &work, Read &&read) const;

  const solver::ProgramGraph &graph;
  // A range per result and per parameter of each function, uninitialized
  // where nothing reached it.
  Ragged<solver::FunctionId, mlir::IntegerValueRange> returns;
  Ragged<solver::FunctionId, mlir::IntegerValueRange> arguments;
  // A bound per value of each function, in its walk order. A function's
  // row is written by the turn of the callers-first schedule that solves
  // it, in no id order, so each function owns its row.
  IndexVector<solver::FunctionId, footprint::Vector<ranges::Bounds>> bounded;
  solver::Work spent;
};

} // namespace idr

MLIR_DECLARE_EXPLICIT_TYPE_ID(idr::Ranges)

#endif // IDR_ANALYSIS_RANGES_H
