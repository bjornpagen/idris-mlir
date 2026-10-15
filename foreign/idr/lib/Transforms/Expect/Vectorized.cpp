// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// vectorized: after the vectorization schedule, some loop computes on
// vectors, and none over words with a parallel dimension stays scalar.

#include "idr/Transforms/Expect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"

using namespace mlir;

namespace idr::expect {

namespace {

// A body the vectorizer takes: words alone, computed by arith and math ops
// and the loop's own indices.
bool wordsAlone(linalg::GenericOp op) {
  for (Operation &inner : op.getRegion().front()) {
    if (isa<linalg::IndexOp, linalg::YieldOp>(inner))
      continue;
    if (inner.getNumRegions() != 0 ||
        !isa_and_nonnull<arith::ArithDialect, math::MathDialect>(inner.getDialect()))
      return false;
  }
  return true;
}

} // namespace

// After the vectorization schedule, in the function the argument names or
// anywhere, some loop computes on vectors, and no linalg.generic with a
// parallel dimension and a body of words alone is left scalar.
LogicalResult vectorized(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "vectorized";
  SmallVector<Operation *> roots =
      rootsOf(module, function, property);
  if (roots.empty())
    return failure();
  bool held = true, vectors = false;
  for (Operation *root : roots)
    root->walk([&](Operation *op) {
      if (isa_and_nonnull<vector::VectorDialect>(op->getDialect()))
        vectors = true;
      auto generic = dyn_cast<linalg::GenericOp>(op);
      if (!generic || generic.getNumParallelLoops() == 0 || !wordsAlone(generic))
        return;
      fail(op->getLoc(), property) << "a loop over words with a parallel dimension stayed scalar in "
                                   << where(op);
      held = false;
    });
  if (!vectors) {
    fail(roots.front()->getLoc(), property) << "no loop computes on vectors"
                                            << (function.empty() ? "" : " in ") << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
