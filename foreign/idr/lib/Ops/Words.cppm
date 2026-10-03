// idr.ops:words: what a loop over an array computes.
export module idr.ops:words;

import idr.mlir;

using namespace mlir;

export namespace idr::ops {

// An element a vector lane computes: an integer or a float.
LogicalResult verifyWord(Operation *op, StringRef what, Type type) {
  if (!isa<IntegerType, FloatType>(type))
    return op->emitOpError() << what << " is " << type
                             << ", and a loop over an array computes machine words: integers "
                                "and floats";
  return success();
}

} // namespace idr::ops
