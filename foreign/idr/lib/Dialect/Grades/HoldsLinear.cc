// Whether a closure or a suspension holds a linear value.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// The operands of either are its captures.
bool idr::holdsLinear(Value value) {
  Operation *made = value.getDefiningOp();
  return isa_and_nonnull<ClosureOp, SuspendOp>(made) &&
         llvm::any_of(made->getOperandTypes(),
                      [](Type type) { return quantityOf(type) == Quantity::One; });
}
