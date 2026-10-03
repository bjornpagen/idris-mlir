// idr.graph:passesonprevious: whether a terminator ends a tail position and
// passes on the results of the op before it.
export module idr.graph:passesonprevious;

import idr.mlir;
import idr.dialect;

using namespace mlir;

export namespace idr::graph {

// Whether `terminator` ends a tail position and passes on exactly the
// results of the op before it.
bool passesOnPrevious(Operation *terminator) {
  Operation *prev = terminator->getPrevNode();
  return isa<func::ReturnOp, idr::YieldOp>(terminator) && prev &&
         llvm::equal(prev->getResults(), terminator->getOperands());
}

} // namespace idr::graph
