// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ranges of the program's integers, bigs and naturals: MLIR's integer
// range analysis on one function at a time, a value it cannot see computed
// starting at the range its type proves, joined across calls by summaries
// over the program graph's components: what each function returns, callees
// first, and what each is passed, callers first, each on the solver
// layer's static schedule, so independent components are solved at once.
// idr-narrow decides the summaries; each function idr-narrow-words narrows
// solves itself, alone, its arguments starting at their summary and each
// call's results at its callee's.
//
// The state of a solve is one function's values; the summaries are a range
// per parameter and per result, and what each function passes each callee
// of another component, which the callee's component joins when it starts.
// Inside a component of two functions or more, or of one that calls
// itself, a summary that would feed itself is its type's whole range, as
// upstream's analysis widens a value a loop keeps changing: a wider range
// is still a range of the value, and every reader takes a range as a bound
// to narrow or version under. Nothing refuses or errors on a range. Each
// component writes its own members' summaries alone, in its members'
// order, and joins only finished components', so the summaries are the
// same bytes at any thread count.
//
// A solve's work is the transfers the range analysis makes over the
// function: each op, call and region entry it visits, each time it visits
// one.
#ifndef IDR_ANALYSIS_RANGES_H
#define IDR_ANALYSIS_RANGES_H

#include "idr/Analysis/Solver/Decision.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Pass/AnalysisManager.h"
#include "mlir/Support/TypeID.h"
#include "llvm/ADT/SmallVector.h"

#include <memory>
#include <optional>

namespace idr {

// A range per position, uninitialized where nothing reached it.
using RangeSummary = llvm::SmallVector<mlir::IntegerValueRange, 2>;

class Ranges : public solver::ReadsAnalyses<Ranges, solver::ProgramGraph> {
public:
  static constexpr llvm::StringLiteral decideStep = "idr-narrow";

  // One function's solve, read by the function pass that made it while it
  // lives; several such solves of different functions run at once.
  class Solved {
  public:
    // The range found for `value`; none where the analysis never reached
    // it, which proves nothing.
    std::optional<mlir::ConstantIntRanges> rangeOf(mlir::Value value) const {
      return Ranges::rangeOf(dataflow, value);
    }

  private:
    friend class Ranges;
    Solved();

    mlir::DataFlowSolver dataflow;
  };

  // The summaries of `program`, an idr.program: its program graph's
  // components callees first for returns, then callers first for
  // arguments, each function solved alone.
  Ranges(mlir::Operation *program, mlir::AnalysisManager &am);

  // `fn`'s solve under the summaries, its transfers added to `work`;
  // failure when MLIR's solver failed, an internal error the reader
  // reports.
  mlir::FailureOr<std::unique_ptr<const Solved>> solve(idr::FuncOp fn, solver::Work &work) const;

  // The one read of an integer range lattice, of this solver or of any
  // other that ran MLIR's integer range analysis.
  static std::optional<mlir::ConstantIntRanges> rangeOf(const mlir::DataFlowSolver &solver,
                                                        mlir::Value value);

  // What a call of the function a call names returns, by result.
  const RangeSummary &returnsOf(mlir::FlatSymbolRefAttr callee) const {
    return returns[graph.id(callee)];
  }

  // The transfers the summaries' solves made, the decide step's work.
  std::uint64_t work() const { return spent.steps(); }

private:
  const solver::ProgramGraph &graph;
  IndexVector<solver::FunctionId, RangeSummary> returns;
  IndexVector<solver::FunctionId, RangeSummary> arguments;
  solver::Work spent;
};

} // namespace idr

MLIR_DECLARE_EXPLICIT_TYPE_ID(idr::Ranges)

#endif // IDR_ANALYSIS_RANGES_H
