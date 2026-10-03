// idr.tail:reaches: whether a block in tail position reaches a self tail
// call, through the matches in tail position on the way.
export module idr.tail:reaches;

import idr.mlir;
import idr.dialect;
import idr.graph;

using namespace mlir;

namespace idr::tail {

bool isTailMatch(Operation *op) { return isa_and_nonnull<idr::MatchOp, idr::MatchLitOp>(op); }

// Whether the block, which ends in a tail position, reaches a self tail call.
bool reachesTailCall(Block &block, func::FuncOp fn) {
  Operation *terminator = block.getTerminator();
  if (!graph::passesOnPrevious(terminator))
    return false;
  Operation *prev = terminator->getPrevNode();
  if (graph::isSelfCall(prev, fn))
    return true;
  if (!isTailMatch(prev))
    return false;
  return llvm::any_of(prev->getRegions(), [&](Region &region) {
    return !region.empty() && reachesTailCall(region.front(), fn);
  });
}

} // namespace idr::tail
