// idr.verify:linearity: worlds and !idr.lin values.
export module idr.verify:linearity;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

namespace {

// Whether each region of `branch` returns straight to it, so that at most
// one runs: the regions of a match or of an scf.if, not those of a loop.
bool exclusiveRegions(RegionBranchOpInterface branch) {
  return llvm::all_of(branch->getRegions(), [&](Region &region) {
    SmallVector<RegionSuccessor> next;
    branch.getSuccessorRegions(region, next);
    return llvm::all_of(next, [](RegionSuccessor &successor) { return successor.isOperation(); });
  });
}

// The uses of one linear value, counted on the worst path. The regions of
// a match, and of any op whose regions exclude each other, are alternative
// paths; a region that may run repeatedly counts twice. A region of several
// blocks, which the contract does not produce, counts every use in it.
class LinearUses {
public:
  explicit LinearUses(Value value) : world(value) {
    Region *home = world.getParentRegion();
    for (OpOperand &use : world.getUses())
      for (Operation *op = use.getOwner(); op; op = op->getParentOp()) {
        if (!holders.insert(op).second)
          break;
        if (op->getParentRegion() == home) {
          top.push_back(op);
          break;
        }
        byBlock[op->getBlock()].push_back(op);
      }
    llvm::DenseMap<Block *, unsigned> order;
    for (Block &block : *home)
      order[&block] = order.size();
    llvm::sort(top, [&](Operation *a, Operation *b) {
      if (a->getBlock() != b->getBlock())
        return order[a->getBlock()] < order[b->getBlock()];
      return a->isBeforeInBlock(b);
    });
  }

  // The first op after which the value has been used twice, if any.
  Operation *secondUse() {
    unsigned total = 0;
    for (Operation *op : top) {
      total += count(op);
      if (total > 1)
        return op;
    }
    return nullptr;
  }

private:
  unsigned count(Region &region) {
    unsigned total = 0;
    for (Block &block : region)
      for (Operation *op : byBlock.lookup(&block))
        total += count(op);
    return total;
  }

  unsigned count(Operation *op) {
    // A view of the value (idr.borrow) is not a use of it: the owner keeps
    // its reference, and the view's uses come before the owner's one use.
    unsigned total =
        isa<BorrowOp>(op) ? 0u : static_cast<unsigned>(llvm::count(op->getOperands(), world));
    if (op->getNumRegions() == 0)
      return total;
    auto branch = dyn_cast<RegionBranchOpInterface>(op);
    bool exclusive = branch && exclusiveRegions(branch);
    unsigned regions = 0;
    for (unsigned index = 0, e = op->getNumRegions(); index < e; ++index) {
      unsigned uses = count(op->getRegion(index));
      if (uses && !exclusive && branch && branch.isRepetitiveRegion(index))
        uses = 2;
      regions = exclusive ? std::max(regions, uses) : regions + uses;
    }
    return total + regions;
  }

  Value world;
  llvm::DenseSet<Operation *> holders;
  SmallVector<Operation *> top;
  llvm::DenseMap<Block *, SmallVector<Operation *>> byBlock;
};

} // namespace

export namespace idr::verify {

// Every value of quantity 1, a world or an !idr.lin, is used at most once
// on every path. Its types say where it may go; this says how often.
LogicalResult linearity(FunctionOpInterface fn) {
  auto check = [&](Value value) -> LogicalResult {
    // A poison is no value: it stands where a path that is never taken
    // needs one (the payload a loop yields on the path that does not use
    // it), so taking it twice takes nothing. Constant hoisting may put one
    // outside a loop, where every use inside repeats.
    if (quantityOf(value.getType()) != Quantity::One || value.getDefiningOp<ub::PoisonOp>())
      return success();
    if (Operation *op = LinearUses(value).secondUse())
      return op->emitOpError(isWorld(value.getType())
                                 ? "uses a world that is already used on the same path"
                                 : "uses a linear value that is already used on the same path");
    return success();
  };
  WalkResult result = fn->walk([&](Block *block) -> WalkResult {
    for (BlockArgument arg : block->getArguments())
      if (failed(check(arg)))
        return WalkResult::interrupt();
    for (Operation &op : *block)
      for (Value value : op.getResults())
        if (failed(check(value)))
          return WalkResult::interrupt();
    return WalkResult::advance();
  });
  return failure(result.wasInterrupted());
}

} // namespace idr::verify
