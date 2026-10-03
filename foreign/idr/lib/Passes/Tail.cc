// Tail position (Passes/Tail.h).

#include "Passes/Tail.h"

using namespace mlir;

namespace idr::passes {

bool inTailPosition(Operation *op) {
  Operation *next = op->getNextNode();
  if (!next || !next->hasTrait<OpTrait::IsTerminator>() ||
      !llvm::equal(op->getResults(), next->getOperands()))
    return false;
  if (isa<func::ReturnOp>(next))
    return true;
  Operation *match = next->getParentOp();
  return isa<YieldOp>(next) && isa<MatchOp, MatchLitOp>(match) && inTailPosition(match);
}

} // namespace idr::passes
