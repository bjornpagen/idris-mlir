// idr.graph:intailposition: tail position, where what an op computes is
// what its function returns.
export module idr.graph:intailposition;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::graph {

// Whether the results of `op` pass unchanged to its function's return: the
// op right after it is the terminator and passes exactly them, and is the
// function's return or the yield of a match in tail position itself. A self
// call there becomes the next iteration of a loop in the same frame
// (idr-tail-loops), and a call of another function on the caller's cycle
// of calls a tail call (idr-tail-calls).
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

} // namespace idr::graph
