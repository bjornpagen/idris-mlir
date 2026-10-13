// What a vectorized loop computes on, what it reads from outside, and how
// often it runs.

#include "idr/Transforms/Narrow.h"

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/AffineMap.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/CastInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "mlir/Transforms/RegionUtils.h"

using namespace mlir;

namespace idr::narrow {

// A loop is vectorized when it computes on vectors, has no results (a loop
// over buffers), and holds nothing but vector ops, the loops of its tiles
// and ops with neither effects nor regions. A tile the vectorizer refused
// keeps its linalg.generic, and a branch or a call keeps its scalar code,
// so a loop holding one is not vectorized, nor is a loop around a
// vectorized one that stores: the tile loops are the outermost such loops.
bool isVectorized(scf::ForOp loop) {
  if (loop->getNumResults() != 0)
    return false;
  bool vectors = false;
  WalkResult walk = loop.walk([&](Operation *op) {
    if (isa_and_nonnull<vector::VectorDialect>(op->getDialect())) {
      vectors = true;
      return WalkResult::advance();
    }
    if (isa<scf::ForOp, scf::YieldOp>(op))
      return WalkResult::advance();
    if (op->getNumRegions() != 0 || !isMemoryEffectFree(op))
      return WalkResult::interrupt();
    return WalkResult::advance();
  });
  return vectors && !walk.wasInterrupted();
}

SetVector<Value> inputsOf(scf::ForOp loop) {
  SetVector<Value> inputs;
  inputs.insert_range(loop->getOperands());
  getUsedValuesDefinedAbove(loop->getRegions(), inputs);
  return inputs;
}

// The version tests an integer wider than 32 bits or an index, no
// constant, whose range the analysis cannot know.
bool testable(Value value) {
  Type type = value.getType();
  return (type.isIndex() || (type.isSignlessInteger() && type.getIntOrFloatBitWidth() > 32)) &&
         !matchPattern(value, m_Constant());
}

bool fits32(const ConstantIntRanges &range) {
  return range.smin().getSignificantBits() <= 32 && range.smax().getSignificantBits() <= 32;
}

// An op computes on integers wider than 32 bits when it is elementwise, no
// cast, and has such an operand or result; on lanes of them when one is a
// vector.
Width widthOf(Operation *op) {
  Width width;
  if (!op->hasTrait<OpTrait::Elementwise>() || isa<CastOpInterface>(op))
    return width;
  auto note = [&](Type type) {
    if (ConstantIntRanges::getStorageBitwidth(type) <= 32)
      return;
    width.wide = true;
    width.lanes |= isa<VectorType>(type);
  };
  for (Type type : op->getOperandTypes())
    note(type);
  for (Type type : op->getResultTypes())
    note(type);
  return width;
}

// Lanes of integers wider than 32 bits are what the narrowing is for.
bool computesWideLanes(scf::ForOp loop) {
  return loop
      .walk([](Operation *op) {
        return widthOf(op).lanes ? WalkResult::interrupt() : WalkResult::advance();
      })
      .wasInterrupted();
}

// A loop runs at most once when its upper bound exceeds its lower bound by
// less than a step, as for the loop of a peeled tile loop's last tile,
// whose bounds are `n - n mod step` and `n`.
bool runsAtMostOnce(scf::ForOp loop) {
  std::optional<int64_t> step = getConstantIntValue(loop.getStep());
  if (!step || *step <= 0)
    return false;
  MLIRContext *ctx = loop.getContext();
  auto span = AffineMap::get(2, 0, getAffineDimExpr(0, ctx) - getAffineDimExpr(1, ctx));
  // An upper bound is open: the span is below it.
  FailureOr<int64_t> bound = ValueBoundsConstraintSet::computeConstantBound(
      presburger::BoundType::UB,
      ValueBoundsConstraintSet::Variable(span,
                                         ValueRange{loop.getUpperBound(), loop.getLowerBound()}));
  return succeeded(bound) && *bound <= *step;
}

} // namespace idr::narrow
