// idr.canon:meets: whether a consumer moved into a match's regions meets
// there, or one match deeper, a value it folds or canonicalizes against
// (:feeds).
export module idr.canon:meets;

import idr.mlir;
import idr.dialect;

import :feeds;

using namespace mlir;
using namespace idr;

namespace {

// Whether some region of the match that defines `result` yields, as that
// result, a value that feeds the consumer holding `use`, or, while `deeper`
// is above 0, the result of a match one of whose regions does so in turn:
// case-of-case moves the consumer on into that match. The bound keeps the
// question as cheap as the matches are wide, however deep they nest, and
// a consumer moves only toward a value it meets within that many moves.
bool yieldsFeeding(OpResult result, OpOperand &use, unsigned deeper) {
  return llvm::any_of(result.getOwner()->getRegions(), [&](Region &region) {
    auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
    if (!yield)
      return false;
    Value value = yield.getOperand(result.getResultNumber());
    if (canon::feeds(value, use))
      return true;
    auto inner = dyn_cast<OpResult>(value);
    return deeper > 0 && inner && isa<MatchOp, MatchLitOp>(inner.getOwner()) &&
           yieldsFeeding(inner, use, deeper - 1);
  });
}

} // namespace

export namespace idr::canon {

// Whether `consumer`, moved into every region of the match that defines
// `result`, meets in some region a value it folds or canonicalizes against,
// there or in a region of a match that region yields the result of: in a
// region of the match, or one match deeper, since a helper's `if` over two
// actions, inlined into a region, leaves the closures the bind folds
// against in the regions of a match the region yields the result of.
bool meetsInSomeRegion(OpResult result, Operation *consumer) {
  return llvm::any_of(consumer->getOpOperands(), [&](OpOperand &use) {
    return use.get() == result && yieldsFeeding(result, use, /*deeper=*/1);
  });
}

} // namespace idr::canon
