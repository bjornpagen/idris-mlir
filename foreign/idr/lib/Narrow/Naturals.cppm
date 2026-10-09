// idr.narrow:naturals: MLIR's integer range analysis, seeing a natural as
// at least 0 and the program's poison as any value, and the solver that
// runs it.
export module idr.narrow:naturals;

import idr.mlir;
import idr.dialect;
import idr.ranges;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::narrow {

// MLIR's analysis starts a value it cannot see computed at every value of
// its type; a natural's type proves more, that it is at least 0.
class NaturalRanges : public IntegerRangeAnalysis {
public:
  // The analysis's identity, which MLIR's TypeID finds by this name.
  static TypeID resolveTypeID() {
    static SelfOwningTypeID id;
    return id;
  }
  using IntegerRangeAnalysis::IntegerRangeAnalysis;

  void setToEntryState(IntegerValueRangeLattice *lattice) override {
    if (isa<NatType>(lattice->getAnchor().getType())) {
      propagateIfChanged(lattice,
                         lattice->join(IntegerValueRange(ranges::rangeOf(ranges::natural()))));
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

// The ranges of `root`'s values, as idr-narrow and idr-in-bounds read them.
export LogicalResult runSolver(DataFlowSolver &solver, Operation *root) {
  solver.load<DeadCodeAnalysis>();
  solver.load<SparseConstantPropagation>();
  solver.load<NaturalRanges>();
  return solver.initializeAndRun(root);
}

// The range the solver recorded for `value`; none where the analysis never
// reached it, which proves nothing. The one read of the lattice: idr-narrow
// turns it into the bounds of a big, idr-narrow-lanes tests whether it fits
// 32 bits, and idr-in-bounds takes it as the range of a word.
export std::optional<ConstantIntRanges> rangeOf(DataFlowSolver &solver, Value value) {
  auto *state = solver.lookupState<IntegerValueRangeLattice>(value);
  if (!state || state->getValue().isUninitialized())
    return std::nullopt;
  return state->getValue().getValue();
}

} // namespace idr::narrow
