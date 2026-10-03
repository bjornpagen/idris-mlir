// idr.ops:matchregions: how every region of a match ends.
export module idr.ops:matchregions;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// Every region ends in idr.yield with the match's result types, or in
// ub.unreachable after a crash.
LogicalResult verifyMatchRegions(Operation *op) {
  for (auto [index, region] : llvm::enumerate(op->getRegions())) {
    Block &block = region.front();
    if (block.empty())
      return op->emitOpError("region #") << index << " is empty";
    Operation *terminator = &block.back();
    if (isa<ub::UnreachableOp>(terminator))
      continue;
    auto yield = dyn_cast<YieldOp>(terminator);
    if (!yield)
      return op->emitOpError("region #")
             << index << " must end in idr.yield or ub.unreachable";
    if (yield.getResults().getTypes() != op->getResultTypes())
      return yield.emitOpError("yields ")
             << yield.getResults().getTypes() << " but the match has results "
             << op->getResultTypes();
  }
  return success();
}

} // namespace idr::ops
