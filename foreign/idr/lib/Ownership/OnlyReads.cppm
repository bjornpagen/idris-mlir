// idr.ownership:onlyreads: a box whose every use reads a field of one
// constructor.
export module idr.ownership:onlyreads;

import idr.mlir;
import idr.dialect;

import :usersin;

using namespace mlir;

namespace idr::ownership {

// The first read of a box that no match takes apart and whose every use
// reads a field of one constructor (a nested pattern reads the fields of a
// box an outer one matched), the point from which the box's constructor
// is known in that read's block; null for any other value.
export FieldOp onlyReads(Value box) {
  if (!isa<BoxType>(unrestricted(box.getType())) || box.use_empty())
    return nullptr;
  FieldOp first;
  for (Operation *user : box.getUsers()) {
    auto read = dyn_cast<FieldOp>(user);
    if (!read || (first && read.getCtorAttr() != first.getCtorAttr()))
      return nullptr;
    if (!first || (read->getBlock() == first->getBlock() && read->isBeforeInBlock(first)))
      first = read;
  }
  // Every use is in the first read's block, at it or after it: from there
  // on the constructor is known. The uses in the block are usersIn's; one
  // before the first read makes that list longer than the uses at the
  // first read or after it, and a use outside the block is in neither.
  Block *block = first->getBlock();
  Operation *before = first->getPrevNode();
  if (usersIn(box, *block, before).size() != usersIn(box, *block, nullptr).size())
    return nullptr;
  if (llvm::any_of(box.getUsers(), [&](Operation *user) {
        return !block->findAncestorOpInBlock(*user);
      }))
    return nullptr;
  return first;
}

} // namespace idr::ownership
