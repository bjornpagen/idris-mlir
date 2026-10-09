// idr.canon:moveout: a read of an element whose next IO is a write of the
// same element moves the element out. The array gives up its reference
// instead of the read taking another, so a value read only to be rebuilt
// and written back (an IORef's modify, a state record's update, a read and
// a write of one element of an array) holds the one reference to its cell
// while it is rebuilt, and counting rebuilds it in that cell. The rule
// names no definition: what it asks is where the world goes.
//
// The world is linear and the read's next world has one use, the write, so
// no IO threaded on that world lies between them. What remains is IO on a
// world of its own (a trusted library's forged one), code whose effects
// MLIR does not know, and a force, whose declared effects do not describe
// what its suspension's code reads: any of these between the two keeps the
// read as it is.
export module idr.canon:moveout;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

namespace {

// Whether `op` may read the array between the read and the write: it may
// read the IO resource, what every array op reads and writes, or nothing
// says what it does (an apply, an indirect call, an op without the
// interface), or it holds a force anywhere inside.
bool mayReadIO(Operation *op) {
  if (op->walk([](ForceOp) { return WalkResult::interrupt(); }).wasInterrupted())
    return true;
  std::optional<SmallVector<MemoryEffects::EffectInstance>> effects = getEffectsRecursively(op);
  return !effects || llvm::any_of(*effects, [](const MemoryEffects::EffectInstance &effect) {
    return isa<MemoryEffects::Read>(effect.getEffect()) &&
           effect.getResource() == IOResource::get();
  });
}

// The write whose world is the next of a read of the same element in its
// block, with nothing between that may read the array: the read moves the
// element out. The write then releases an empty place, which releases
// nothing, and moves its value in as before.
struct MoveOutBeforeSet : OpRewritePattern<ArraySetOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(ArraySetOp set, PatternRewriter &rewriter) const final {
    auto get = set.getWorld().getDefiningOp<ArrayGetOp>();
    if (!get || get.getMoves() || get.getNext() != set.getWorld() || !get.getNext().hasOneUse() ||
        get->getBlock() != set->getBlock() ||
        !sameElement(get.getArray(), get.getIndices(), set.getArray(), set.getIndices()))
      return failure();
    // An element that holds no reference has none to give up.
    SymbolTableCollection symbols;
    if (!holdsReferences(get.getArrayType().getElementType(), symbols, get))
      return failure();
    for (Operation *op = get->getNextNode(); op != set.getOperation(); op = op->getNextNode())
      if (mayReadIO(op))
        return failure();
    rewriter.modifyOpInPlace(get, [&] { get.setMoves(true); });
    return success();
  }
};

} // namespace

export namespace idr::canon {

// Adds the pattern that moves an element out of its array for the write
// that follows.
void addMoveOutPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<MoveOutBeforeSet>(context);
}

} // namespace idr::canon
