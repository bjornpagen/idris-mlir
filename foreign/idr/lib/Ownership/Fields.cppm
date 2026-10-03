// idr.ownership:fields: the fields a take of a box gives, and the uses a
// take placed at a point has already run before. Nothing here is exported:
// takeAt and keepsCountedField share it.
export module idr.ownership:fields;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

// Whether `use` is at `at` in `block` or after it, itself or inside an op
// there: where a take placed at `at` has already run.
bool fromPoint(Block &block, Block::iterator at, OpOperand &use) {
  Operation *top = block.findAncestorOpInBlock(*use.getOwner());
  return top && at != block.end() && !top->isBeforeInBlock(&*at);
}

// The fields of `box`, built by `ctor`, that a take of it gives: the
// arguments of `fields` (the case region that bound them, when one did) and
// the results of the idr.field reads of the box, each with its index.
void eachField(Value box, CtorOp ctor, Block *fields, function_ref<void(Value, unsigned)> f) {
  if (fields)
    for (BlockArgument arg : fields->getArguments())
      f(arg, arg.getArgNumber());
  for (Operation *user : llvm::make_early_inc_range(box.getUsers()))
    if (auto read = dyn_cast<FieldOp>(user); read && read.getCtor() == ctor.getSymName())
      f(read.getResult(), static_cast<unsigned>(read.getIndex()));
}

} // namespace idr::ownership
