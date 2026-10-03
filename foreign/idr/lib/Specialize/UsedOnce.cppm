// idr.specialize:usedonce: whether a shape has no use but the one that
// reads it.
export module idr.specialize:usedonce;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::specialize {

// Whether the shape of `value` has no use but the one that reads it: each
// operation that built it is used once. A call on such a shape takes its
// leaves alone once the shape is erased.
bool usedOnce(mlir::Value value) {
  Operation *def = value.getDefiningOp();
  if (!isa_and_nonnull<ConOp, ClosureOp, LinEnterOp>(def))
    return true;
  return value.hasOneUse() && llvm::all_of(def->getOperands(), usedOnce);
}

} // namespace idr::specialize
