// Tail position.
module idr.graph;

import idr.mlir;
import idr.dialect;

using namespace mlir;

bool idr::graph::inTailPosition(Operation *op) {
  Operation *next = op->getNextNode();
  if (!next || !next->hasTrait<OpTrait::IsTerminator>() ||
      !llvm::equal(op->getResults(), next->getOperands()))
    return false;
  if (isa<func::ReturnOp>(next))
    return true;
  Operation *match = next->getParentOp();
  return isa<YieldOp>(next) && isa<MatchOp, MatchLitOp>(match) && inTailPosition(match);
}
