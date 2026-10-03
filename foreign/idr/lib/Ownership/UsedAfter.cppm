// idr.ownership:usedafter: whether a value is used after an op.
export module idr.ownership:usedafter;

import idr.mlir;

import :arrayloop;

using namespace mlir;

namespace idr::ownership {

// Whether `value` is used after `op`: later in its block, or after an op
// that holds that block, up to the block that defines it; always, from
// inside the body of a loop the value comes from outside of.
export bool usedAfter(Value value, Operation *op) {
  Block *home = value.getParentBlock();
  for (Operation *at = op; at; at = at->getParentOp()) {
    Block *block = at->getBlock();
    if (!block)
      return false;
    for (Operation *user : value.getUsers()) {
      Operation *top = block->findAncestorOpInBlock(*user);
      if (top && at->isBeforeInBlock(top))
        return true;
    }
    if (block == home || isa<func::FuncOp>(block->getParentOp()))
      return false;
    // The body of a loop runs again: the next iteration uses the value.
    if (isArrayLoop(block->getParentOp()))
      return true;
  }
  return false;
}

} // namespace idr::ownership
