// idr.ownership:regions: what counting asks of a region: whether a value is
// used in it, and whether its block ends in a crash, which counting leaves
// alone. Nothing here is exported: counting's steps share it.
export module idr.ownership:regions;

import idr.mlir;

using namespace mlir;

namespace idr::ownership {

// Whether a use of `value` is inside `region`.
bool usedIn(Value value, Region &region) {
  return llvm::any_of(value.getUses(), [&](OpOperand &use) {
    return region.isAncestor(use.getOwner()->getParentRegion());
  });
}

// Whether `block` ends in a crash.
bool endsInCrash(Block &block) { return !block.empty() && isa<ub::UnreachableOp>(block.back()); }

} // namespace idr::ownership
