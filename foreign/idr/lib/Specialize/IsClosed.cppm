// idr.specialize:isclosed: whether a value is closed.
export module idr.specialize:isclosed;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::specialize {

// Whether `value` is closed: a constant, or a constructor or closure of
// closed values.
bool isClosed(mlir::Value value) {
  if (matchPattern(value, m_Constant()))
    return true;
  Operation *def = value.getDefiningOp();
  return isa_and_nonnull<ConOp, ClosureOp>(def) && llvm::all_of(def->getOperands(), isClosed);
}

} // namespace idr::specialize
