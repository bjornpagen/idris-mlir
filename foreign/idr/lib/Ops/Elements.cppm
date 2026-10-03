// idr.ops:elements: what moves into an array or out of it.
export module idr.ops:elements;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// An element moves into an array, or out of it, at the element type at any
// grade: plain before idr-rc, and owned after it when it holds references.
LogicalResult verifyElement(Operation *op, StringRef what, Type type, MemRefType array) {
  if (view(type) != array.getElementType())
    return op->emitOpError() << what << " has type " << type << ", but the array holds "
                             << array.getElementType();
  return success();
}

} // namespace idr::ops
