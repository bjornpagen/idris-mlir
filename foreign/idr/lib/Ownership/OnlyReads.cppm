// idr.ownership:onlyreads: a box whose every use reads a field of one
// constructor.
export module idr.ownership:onlyreads;

import idr.mlir;
import idr.dialect;

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
  // on the constructor is known.
  Block *block = first->getBlock();
  for (Operation *user : box.getUsers()) {
    Operation *top = block->findAncestorOpInBlock(*user);
    if (!top || top->isBeforeInBlock(first))
      return nullptr;
  }
  return first;
}

} // namespace idr::ownership
