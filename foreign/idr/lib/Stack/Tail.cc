// Tail position (Stack/Tail.h).

#include "Stack/Tail.h"

using namespace mlir;

namespace idr::stack {

bool inTailPosition(Operation *op) {
  Operation *next = op->getNextNode();
  if (!next || !llvm::equal(op->getResults(), next->getOperands()))
    return false;
  if (isa<func::ReturnOp>(next))
    return true;
  return isa<YieldOp>(next) && inTailPosition(next->getParentOp());
}

} // namespace idr::stack
