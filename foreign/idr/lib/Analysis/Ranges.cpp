// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The seeded range analysis: MLIR's integer range analysis, seeing a natural
// as at least 0 and the program's poison as any value, solved once over the
// module across calls.

#include "idr/Analysis/Ranges.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Ranges.h"

#include "mlir/Analysis/DataFlow/IntegerRangeAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Support/TypeID.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace mlir::dataflow;

namespace {

// MLIR's analysis starts a value it cannot see computed at every value of
// its type; a natural's type proves more, that it is at least 0. The type
// is read as written: a natural under a grade is not seeded by it.
class NaturalRanges : public IntegerRangeAnalysis {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(NaturalRanges)
  using IntegerRangeAnalysis::IntegerRangeAnalysis;

  void setToEntryState(IntegerValueRangeLattice *lattice) override {
    if (isa<idr::NatType>(lattice->getAnchor().getType())) {
      propagateIfChanged(lattice, lattice->join(IntegerValueRange(
                                      idr::ranges::rangeOf(idr::ranges::natural()))));
      return;
    }
    IntegerRangeAnalysis::setToEntryState(lattice);
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

Ranges::Ranges(Operation *op) : dataflow(DataFlowConfig().setInterprocedural(true)) {
  auto module = cast<ModuleOp>(op);
  // The integer range analysis is silent without dead code analysis, and
  // reads constants through constant propagation.
  loadBaselineAnalyses(dataflow);
  dataflow.load<NaturalRanges>();
  solved = succeeded(dataflow.initializeAndRun(module));
  owned = llvm::any_of(module.getOps<FuncOp>(),
                       [](FuncOp fn) { return ownership::inOwnedStage(fn); });
}

std::optional<ConstantIntRanges> Ranges::rangeOf(const DataFlowSolver &solver, Value value) {
  const auto *state = solver.lookupState<IntegerValueRangeLattice>(value);
  if (!state || state->getValue().isUninitialized())
    return std::nullopt;
  return state->getValue().getValue();
}

} // namespace idr
