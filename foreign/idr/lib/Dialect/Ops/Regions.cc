// idr.lambda and idr.delay, a closure and a suspension whose body is their
// region until idr-isolate gives it a function of its own; and where the
// yield that ends a region goes.

#include "idr/Idr.h"

#include "mlir/Transforms/RegionUtils.h"

using namespace mlir;
using namespace idr;

namespace {

// The body ends in idr.yield of `results`, or in ub.unreachable after a
// crash. The block is not empty (SingleBlock), so it has an op to end in;
// the yields of the matches inside it are theirs.
LogicalResult verifyEnd(Operation *op, Block &body, TypeRange results) {
  Operation *end = &body.back();
  if (isa<ub::UnreachableOp>(end))
    return success();
  auto yield = dyn_cast<YieldOp>(end);
  if (!yield)
    return op->emitOpError("must end in idr.yield or ub.unreachable");
  if (yield.getResults().getTypes() != results)
    return yield.emitOpError("yields ") << yield.getResults().getTypes() << ", but its "
                                        << op->getName() << " has results " << results;
  return success();
}

} // namespace

// The block is the body of the function the closure is of: it takes the
// closure's parameters and yields its results.
LogicalResult LambdaOp::verify() {
  FnType type = getType();
  Block &body = getBody().front();
  if (body.getArgumentTypes() != type.getInputs())
    return emitOpError("takes ") << body.getArgumentTypes() << ", but its type " << type
                                 << " takes " << type.getInputs();
  return verifyEnd(getOperation(), body, type.getResults());
}

// A force passes nothing, so the block takes nothing, and yields the
// suspension's value. A world passes only as an argument or a result, never
// into a suspension, so the body uses none from above.
LogicalResult DelayOp::verify() {
  Block &body = getBody().front();
  if (body.getNumArguments() != 0)
    return emitOpError("takes ") << body.getArgumentTypes()
                                 << ", but a suspension's body takes nothing";
  Type value = cast<LazyType>(unrestricted(getType())).getValue();
  if (failed(verifyEnd(getOperation(), body, value)))
    return failure();
  bool worldAbove = false;
  visitUsedValuesDefinedAbove(getBody(), getBody(), [&](OpOperand *use) {
    worldAbove = worldAbove || isWorld(use->get().getType());
  });
  if (worldAbove)
    return emitOpError("uses a world from above; a world passes only as an argument or result");
  return success();
}

// A match and an array loop branch into their regions, and the yield goes
// on where its parent says. A lambda's or a delay's body runs when the
// closure is applied or the suspension forced, not when the op runs, so the
// yield that ends it goes to no region: the op is no region branch.
void YieldOp::getSuccessorRegions(ArrayRef<Attribute>, SmallVectorImpl<RegionSuccessor> &regions) {
  Operation *parent = (*this)->getParentOp();
  if (isa<LambdaOp, DelayOp>(parent))
    return;
  cast<RegionBranchOpInterface>(parent).getSuccessorRegions(
      RegionBranchPoint(cast<RegionBranchTerminatorOpInterface>(getOperation())), regions);
}
