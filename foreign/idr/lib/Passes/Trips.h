// How often a loop runs, as upstream's value bounds see its bounds: for
// idr-narrow-lanes, which versions no loop that runs at most once, and for
// the property that states what it versions (Expect/Loops.cc).
#pragma once

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"

namespace idr::passes {

// Whether `loop` runs at most once: its upper bound exceeds its lower bound
// by less than a step, as for the loop of a peeled tile loop's last tile,
// whose bounds are `n - n mod step` and `n`.
inline bool runsAtMostOnce(mlir::scf::ForOp loop) {
  std::optional<int64_t> step = mlir::getConstantIntValue(loop.getStep());
  if (!step || *step <= 0)
    return false;
  mlir::MLIRContext *ctx = loop.getContext();
  auto span = mlir::AffineMap::get(2, 0, mlir::getAffineDimExpr(0, ctx) - mlir::getAffineDimExpr(1, ctx));
  // An upper bound is open: the span is below it.
  mlir::FailureOr<int64_t> bound = mlir::ValueBoundsConstraintSet::computeConstantBound(
      mlir::presburger::BoundType::UB,
      mlir::ValueBoundsConstraintSet::Variable(span, mlir::ValueRange{loop.getUpperBound(),
                                                                       loop.getLowerBound()}));
  return mlir::succeeded(bound) && *bound <= *step;
}

} // namespace idr::passes
