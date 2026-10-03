// Whether an op calls the function it is in, by name.
module idr.graph;

import idr.mlir;

using namespace mlir;

bool idr::graph::isSelfCall(Operation *op, func::FuncOp fn) {
  auto call = dyn_cast_or_null<func::CallOp>(op);
  return call && call.getCallee() == fn.getSymName();
}
