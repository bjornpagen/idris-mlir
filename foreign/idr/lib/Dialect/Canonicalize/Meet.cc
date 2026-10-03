// The values a consumer moved into a match's regions meets there: the
// profit of case-of-case and of moving a value into regions.

#include "Dialect/Canonicalize/Matches.h"

#include "mlir/IR/Matchers.h"

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

// A constant, a constructor, a closure, or, for output and the first
// character, a string builder; and a call's result, for the elimination
// that raising moves into a clone of the callee once the two meet.
bool canon::feeds(Value value, OpOperand &use) {
  Operation *consumer = use.getOwner();
  if (isa_and_nonnull<func::CallOp>(value.getDefiningOp()))
    return eliminationAt(use).has_value();
  // A linear position the value only passes on the way changes nothing a
  // consumer folds against: the consumer of a linear value is its use, and
  // what reads the use sees through the pair.
  value = throughLinear(value);
  if (matchPattern(value, m_Constant()))
    return true;
  Operation *def = value.getDefiningOp();
  if (isa_and_nonnull<ConOp, ClosureOp>(def))
    return true;
  return isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(def) &&
         isa<PutStrOp, StrHeadOp>(consumer);
}

// In a region of the match, or one match deeper: a helper's `if` over two
// actions, inlined into a region, leaves the closures the bind folds
// against in the regions of a match the region yields the result of.
bool canon::meetsInSomeRegion(OpResult result, Operation *consumer) {
  return llvm::any_of(consumer->getOpOperands(), [&](OpOperand &use) {
    return use.get() == result && yieldsFeeding(result, use, /*deeper=*/1);
  });
}
