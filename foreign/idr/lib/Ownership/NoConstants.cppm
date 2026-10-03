// idr.ownership:noconstants: reachability alone, for exclusivity's solver.
// Nothing here is exported.
export module idr.ownership:noconstants;

import idr.mlir;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::ownership {

// Reachability alone. The dead-code analysis asks a constant lattice which
// region a branch takes, and a region only a constant would skip is the
// canonicalizer's to fold, not the solver's to leave ungraded: every value
// is a constant it does not know, so every region can run.
class NoConstants : public SparseForwardDataFlowAnalysis<Lattice<ConstantValue>> {
public:
  // The analysis's identity, which MLIR's TypeID finds by this name.
  static TypeID resolveTypeID() {
    static SelfOwningTypeID id;
    return id;
  }
  using SparseForwardDataFlowAnalysis::SparseForwardDataFlowAnalysis;

  LogicalResult visitOperation(Operation *, ArrayRef<const Lattice<ConstantValue> *>,
                               ArrayRef<Lattice<ConstantValue> *> results) override {
    for (Lattice<ConstantValue> *lattice : results)
      setToEntryState(lattice);
    return success();
  }

  void setToEntryState(Lattice<ConstantValue> *lattice) override {
    propagateIfChanged(lattice, lattice->join(ConstantValue::getUnknownConstant()));
  }
};

} // namespace idr::ownership
