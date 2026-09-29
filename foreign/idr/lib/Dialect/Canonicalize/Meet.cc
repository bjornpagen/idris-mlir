// The values a consumer moved into a match's regions meets there: the
// profit of case-of-case and of moving a value into regions.

#include "Dialect/Canonicalize/Matches.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

// A constant, a constructor, a closure, or, for output and the first
// character, a string builder.
bool canon::feeds(Value value, Operation *consumer) {
  if (matchPattern(value, m_Constant()))
    return true;
  Operation *def = value.getDefiningOp();
  if (isa_and_nonnull<ConOp, ClosureOp>(def))
    return true;
  return isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(def) &&
         isa<PutStrOp, StrHeadOp>(consumer);
}

namespace {

bool yieldsBuiltString(OpResult result);

// Whether a region's `yield` of `value` gives output or the first character,
// moved into the region, a string builder to meet: `value` is built there,
// or is the result of a match in the region's block (where the consumer
// lands, next to it) that yields a built string in turn.
bool buildsString(YieldOp yield, Value value) {
  Operation *def = value.getDefiningOp();
  if (isa_and_nonnull<StrAppendOp, StrConsOp, StrFromCharOp, StrShowOp>(def))
    return true;
  return isa_and_nonnull<MatchOp, MatchLitOp>(def) && def->getBlock() == yield->getBlock() &&
         yieldsBuiltString(cast<OpResult>(value));
}

// Whether some region of the match that defines `result` yields a string that
// output or the first character, moved in one match at a time, would meet
// being built.
//
// Only these consumers look through nested matches. Each is a single op
// without regions, so moving it into a match copies one op per region, and
// the copies stop at the innermost matches: what is added is bounded by the
// number of regions. A consumer with regions of its own, another match,
// copied level after level would multiply its size by the number of leaves.
//
// The matches followed are nested, each in a region of the one before, so no
// region is visited twice: the work is bounded by the size of the outermost
// match.
bool yieldsBuiltString(OpResult result) {
  return llvm::any_of(result.getOwner()->getRegions(), [&](Region &region) {
    auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
    return yield && buildsString(yield, yield.getOperand(result.getResultNumber()));
  });
}

// Whether `consumer`, moved into the region that ends in `yield`, meets there
// the value yielded in place of `result`, or, for output and the first
// character, a string being built in a match nested there.
bool meetsInRegion(YieldOp yield, OpResult result, Operation *consumer) {
  Value value = yield.getOperand(result.getResultNumber());
  return canon::feeds(value, consumer) ||
         (isa<PutStrOp, StrHeadOp>(consumer) && buildsString(yield, value));
}

} // namespace

bool canon::meetsInSomeRegion(OpResult result, Operation *consumer) {
  return llvm::any_of(result.getOwner()->getRegions(), [&](Region &region) {
    auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
    return yield && meetsInRegion(yield, result, consumer);
  });
}
