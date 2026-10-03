// Whether a loop runs at most once.
module idr.graph;

import idr.mlir;

bool idr::graph::runsAtMostOnce(mlir::scf::ForOp loop) {
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
