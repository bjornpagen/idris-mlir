// idr.ownership:callee: the function a call calls.
export module idr.ownership:callee;

import idr.mlir;

using namespace mlir;

namespace idr::ownership {

// The function a call calls, or null.
export func::FuncOp callee(func::CallOp call, SymbolTableCollection &symbols) {
  return symbols.lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr());
}

} // namespace idr::ownership
