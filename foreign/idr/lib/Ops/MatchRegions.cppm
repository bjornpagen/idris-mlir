// idr.ops:matchregions: how every region of a match ends.
export module idr.ops:matchregions;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// Every region ends in idr.yield, or in ub.unreachable after a crash. Each
// region is one block that is not empty (SingleBlock), so it has an op to
// end in. What a yield gives is the match's results, which
// RegionBranchOpInterface checks along the edge from the yield to the match.
LogicalResult verifyMatchRegions(Operation *op) {
  for (auto [index, region] : llvm::enumerate(op->getRegions()))
    if (!isa<YieldOp, ub::UnreachableOp>(region.front().back()))
      return op->emitOpError("region #")
             << index << " must end in idr.yield or ub.unreachable";
  return success();
}

} // namespace idr::ops
