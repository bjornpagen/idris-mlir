// idr.specialize:eraseunused: erasing the shapes a clone's call no longer
// needs.
export module idr.specialize:eraseunused;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::specialize {

// Erases the operations that built the shapes of `values` once nothing
// uses them. They hold the leaves, which the clone's call now takes itself:
// a linear leaf used by both would be used twice.
void eraseUnused(llvm::ArrayRef<mlir::Value> values) {
  auto shapeOp = [](Value value) -> Operation * {
    Operation *def = value.getDefiningOp();
    return isa_and_nonnull<ConOp, ClosureOp, LinEnterOp>(def) ? def : nullptr;
  };
  // The operations, not the values: a value passed twice names one
  // operation, which is erased once.
  llvm::SetVector<Operation *> candidates;
  for (Value value : values)
    if (Operation *def = shapeOp(value))
      candidates.insert(def);
  while (!candidates.empty()) {
    Operation *op = candidates.pop_back_val();
    if (!op->use_empty())
      continue;
    for (Value part : op->getOperands())
      if (Operation *def = shapeOp(part))
        candidates.insert(def);
    op->erase();
  }
}

} // namespace idr::specialize
