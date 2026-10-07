// idr.ownership:usersin: the ops of a block that use a value.
export module idr.ownership:usersin;

import idr.mlir;

using namespace mlir;

namespace idr::ownership {

// The op of `block` that holds `use`, when that op is strictly after
// `after` (anywhere in the block when `after` is null). Null when the use
// is not in the block, or is `after` or earlier. The one walk of a use up
// to the block that holds it.
Operation *heldIn(Block &block, OpOperand &use, Operation *after) {
  Operation *top = block.findAncestorOpInBlock(*use.getOwner());
  if (top && (!after || after->isBeforeInBlock(top)))
    return top;
  return nullptr;
}

// The ops of `block` after `after` (from its start when null) that use
// `value`, themselves or in their regions, in order.
export SmallVector<Operation *> usersIn(Value value, Block &block, Operation *after) {
  SmallVector<Operation *> users;
  for (OpOperand &use : value.getUses())
    if (Operation *top = heldIn(block, use, after))
      users.push_back(top);
  llvm::sort(users, [](Operation *a, Operation *b) { return a->isBeforeInBlock(b); });
  users.erase(std::unique(users.begin(), users.end()), users.end());
  return users;
}

} // namespace idr::ownership
