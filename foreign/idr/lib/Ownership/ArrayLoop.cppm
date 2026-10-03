// idr.ownership:arrayloop: the loops over an array, whose body runs once
// per index.
export module idr.ownership:arrayloop;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

// Whether `op`'s region is the body of a loop over an array
// (idr.array.generate, idr.array.fold): it runs once per index it covers,
// so a value from outside it is used again after any op in it.
export bool isArrayLoop(Operation *op) { return isa<ArrayGenerateOp, ArrayFoldOp>(op); }

} // namespace idr::ownership
