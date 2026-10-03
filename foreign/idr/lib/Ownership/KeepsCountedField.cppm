// idr.ownership:keepscountedfield: whether a take where a box dies saves
// anything over a drop.
export module idr.ownership:keepscountedfield;

import idr.mlir;
import idr.dialect;

import :counting;
import :fields;

using namespace mlir;

namespace idr::ownership {

// Whether `box`, built by `ctor`, keeps a field that holds references past
// `at` in `block`, where it dies: a field of it (as takeAt finds them) used
// at that point or after. Only then does a take there save anything over a
// drop, as Perceus specializes a drop only where the children are used: a
// field that lives on moves out of an unshared cell instead of taking a
// reference of its own while the box drops the cell's. A field that dies
// with the box is dropped either way, and one that holds no reference has
// nothing to move.
export bool keepsCountedField(Value box, CtorOp ctor, Block &block, Block::iterator at,
                              Block *fields) {
  Counting counting(ctor->getParentOfType<ModuleOp>());
  bool kept = false;
  eachField(box, ctor, fields, [&](Value field, unsigned) {
    kept = kept || (counting.counted(field.getType()) &&
                    llvm::any_of(field.getUses(),
                                 [&](OpOperand &use) { return fromPoint(block, at, use); }));
  });
  return kept;
}

} // namespace idr::ownership
