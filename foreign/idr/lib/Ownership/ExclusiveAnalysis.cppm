// idr.ownership:exclusiveanalysis: the sparse forward dataflow analysis of
// exclusivity, on MLIR's solver. Nothing here is exported: inferExclusive
// loads it.
export module idr.ownership:exclusiveanalysis;

import idr.mlir;
import idr.dialect;

import :cells;
import :followed;
import :reachesonlyatoms;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::ownership {

class ExclusiveAnalysis : public SparseForwardDataFlowAnalysis<CellsLattice> {
public:
  // The analysis's identity, which MLIR's TypeID finds by this name.
  static TypeID resolveTypeID() {
    static SelfOwningTypeID id;
    return id;
  }
  using SparseForwardDataFlowAnalysis::SparseForwardDataFlowAnalysis;

  LogicalResult visitOperation(Operation *op, ArrayRef<const CellsLattice *> operands,
                               ArrayRef<CellsLattice *> results) override {
    // A constructor reaches its box fields' cells; a stack cell is lent
    // to whoever holds it, never theirs.
    if (isa<ConOp, ReuseOp>(op)) {
      Sharing sharing = op->hasAttr("idr.stack") ? Sharing::Shared : Sharing::Exclusive;
      for (auto [operand, lattice] : llvm::zip(op->getOperands(), operands))
        if (followed(operand) && !isa<TokenType>(unrestricted(operand.getType())))
          sharing = std::max(sharing, held(lattice));
      return set(results[0], sharing);
    }
    // A copy of static data that reaches no cell but atoms is in every
    // exclusive tree; any other copy shares its cells with the original.
    if (auto dup = dyn_cast<DupOp>(op))
      return set(results[0],
                 reachesOnlyAtoms(dup.getValue()) ? Sharing::Exclusive : Sharing::Shared);
    // The fields of an exclusive value are exclusive: it alone reached
    // them. So is the cell it leaves behind.
    if (isa<TakeOp>(op)) {
      Sharing sharing = held(operands[0]);
      for (auto [result, lattice] : llvm::zip(op->getResults(), results))
        if (followed(result))
          propagateIfChanged(lattice, lattice->join(Cells::of(sharing)));
      return success();
    }
    if (isa<LinEnterOp, LinUseOp>(op))
      return set(results[0], held(operands[0]));
    if (isa<ShareOp>(op))
      return set(results[0], Sharing::Shared);
    // Poison is no value: nothing reaches its cells.
    if (isa<ub::PoisonOp>(op))
      return set(results[0], Sharing::Exclusive);
    for (auto [result, lattice] : llvm::zip(op->getResults(), results))
      if (followed(result))
        propagateIfChanged(lattice, lattice->join(Cells::of(Sharing::Shared)));
    return success();
  }

  // A value the module does not show every source of is shared.
  void setToEntryState(CellsLattice *lattice) override {
    propagateIfChanged(lattice, lattice->join(Cells::of(Sharing::Shared)));
  }

private:
  // What an operand holds, optimistically: unknown counts as exclusive
  // until a path shares it.
  static Sharing held(const CellsLattice *lattice) {
    return lattice->getValue().sharing == Sharing::Shared ? Sharing::Shared : Sharing::Exclusive;
  }

  LogicalResult set(CellsLattice *lattice, Sharing sharing) {
    propagateIfChanged(lattice, lattice->join(Cells::of(sharing)));
    return success();
  }
};

} // namespace idr::ownership
