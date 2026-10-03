// Whether a terminator ends a tail position and passes on the results of
// the op before it.
module idr.graph;

import idr.mlir;
import idr.dialect;

using namespace mlir;

bool idr::graph::passesOnPrevious(Operation *terminator) {
  Operation *prev = terminator->getPrevNode();
  return isa<func::ReturnOp, idr::YieldOp>(terminator) && prev &&
         llvm::equal(prev->getResults(), terminator->getOperands());
}
