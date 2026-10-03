// idr.graph:isselfcall: whether an op calls the function it is in, by name.
export module idr.graph:isselfcall;

import idr.mlir;

using namespace mlir;

export namespace idr::graph {

// Whether `op` calls `fn` itself.
bool isSelfCall(Operation *op, func::FuncOp fn) {
  auto call = dyn_cast_or_null<func::CallOp>(op);
  return call && call.getCallee() == fn.getSymName();
}

} // namespace idr::graph
