// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The seeded range analysis: MLIR's integer range analysis, starting a
// value it cannot see computed at the range its type proves and seeing the
// program's poison as any value, solved once over the program across calls.

#include "idr/Analysis/Ranges.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"

#include "mlir/Analysis/DataFlow/IntegerRangeAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Support/TypeID.h"

using namespace mlir;
using namespace mlir::dataflow;

namespace {

// MLIR's analysis starts a value it cannot see computed at every value of
// its type's width; the type proves the range idr::ranges::ofType gives,
// which for a natural is at least 0, whatever its grade.
class NaturalRanges : public IntegerRangeAnalysis {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NaturalRanges)
  using IntegerRangeAnalysis::IntegerRangeAnalysis;

  void setToEntryState(IntegerValueRangeLattice *lattice) override {
    propagateIfChanged(lattice,
                       lattice->join(idr::ranges::ofType(lattice->getAnchor().getType())));
  }

  // A ub.poison is a value of the program, given where nothing reads it (as
  // idr-tail-loops passes it on the path that does not take it), and may be
  // any value: every range holds of it, so it adds nothing to the range of
  // a merge it flows into.
  LogicalResult visitOperation(Operation *op, ArrayRef<const IntegerValueRangeLattice *> operands,
                               ArrayRef<IntegerValueRangeLattice *> results) override {
    if (isa<ub::PoisonOp>(op))
      return success();
    return IntegerRangeAnalysis::visitOperation(op, operands, results);
  }
};

} // namespace

namespace idr {

Ranges::Solved::Solved() : dataflow(DataFlowConfig().setInterprocedural(true)) {}

Ranges::Ranges(Operation *program, AnalysisManager &)
    : solution([program]() -> FailureOr<std::unique_ptr<const Solved>> {
        std::unique_ptr<Solved> solve(new Solved());
        // The integer range analysis is silent without dead code analysis,
        // and reads constants through constant propagation.
        loadBaselineAnalyses(solve->dataflow);
        solve->dataflow.load<NaturalRanges>();
        if (failed(solve->dataflow.initializeAndRun(program)))
          return failure();
        return std::unique_ptr<const Solved>(std::move(solve));
      }()) {}

FailureOr<std::reference_wrapper<const Ranges::Solved>> Ranges::solved() const {
  if (failed(solution))
    return failure();
  return std::cref(**solution);
}

std::optional<ConstantIntRanges> Ranges::rangeOf(const DataFlowSolver &solver, Value value) {
  const auto *state = solver.lookupState<IntegerValueRangeLattice>(value);
  if (!state || state->getValue().isUninitialized())
    return std::nullopt;
  return state->getValue().getValue();
}

} // namespace idr
