// idr.ownership:arrayloop: the loops over an array, whose body runs once
// per index.
export module idr.ownership:arrayloop;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

// Whether `op`'s region is the body of a loop over an array
// (idr.array.generate, idr.array.fold): it runs once per index it covers,
// so a value from outside it is used again after any op in it. The body
// says that it runs again by being its own successor. A body that only
// crashes has no such edge, because ub.unreachable is not a region-branch
// terminator, and still covers each index up to the crash.
export bool isArrayLoop(Operation *op) {
  if (!isa<ArrayGenerateOp, ArrayFoldOp>(op) || op->getRegion(0).empty())
    return false;
  Block &body = op->getRegion(0).front();
  if (!body.empty() && isa<ub::UnreachableOp>(body.getTerminator()))
    return true;
  return cast<RegionBranchOpInterface>(op).isRepetitiveRegion(0);
}

} // namespace idr::ownership
