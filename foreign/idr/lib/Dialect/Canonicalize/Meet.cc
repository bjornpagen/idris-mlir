// The values a consumer moved into a match's regions meets there: the
// profit of case-of-case and of moving a value into regions.

#include "Dialect/Canonicalize/Matches.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

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

bool canon::meetsInSomeRegion(OpResult result, Operation *consumer) {
  return llvm::any_of(consumer->getOpOperands(), [&](OpOperand &use) {
    if (use.get() != result)
      return false;
    return llvm::any_of(result.getOwner()->getRegions(), [&](Region &region) {
      auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
      return yield && feeds(yield.getOperand(result.getResultNumber()), use);
    });
  });
}
