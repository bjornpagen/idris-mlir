// idr.ownership:usersin: the ops of a block that use a value.
export module idr.ownership:usersin;

import idr.mlir;

using namespace mlir;

namespace idr::ownership {

// The ops of `block` after `after` (from its start when null) that use
// `value`, themselves or in their regions, in order.
export SmallVector<Operation *> usersIn(Value value, Block &block, Operation *after) {
  SmallVector<Operation *> users;
  for (Operation *user : value.getUsers()) {
    Operation *top = block.findAncestorOpInBlock(*user);
    if (top && (!after || after->isBeforeInBlock(top)))
      users.push_back(top);
  }
  llvm::sort(users, [](Operation *a, Operation *b) { return a->isBeforeInBlock(b); });
  users.erase(std::unique(users.begin(), users.end()), users.end());
  return users;
}

} // namespace idr::ownership
