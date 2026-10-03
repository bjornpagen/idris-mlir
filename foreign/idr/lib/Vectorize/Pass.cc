// idr-vectorize: each loop over an array the vectorizer takes computes on
// the target's lanes, as idr.vectorize tiles and vectorizes it.

#include "idr/Idr.h"

#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"

namespace idr {
#define GEN_PASS_DEF_IDRVECTORIZE
#include "idr/Passes.h.inc"
} // namespace idr

import idr.vectorize;

namespace {

struct Vectorize : idr::impl::IdrVectorizeBase<Vectorize> {
  using IdrVectorizeBase::IdrVectorizeBase;

  void runOnOperation() override {
    mlir::FailureOr<idr::vectorize::Vectorized> done = idr::vectorize::vectorize(getOperation());
    if (mlir::failed(done))
      return signalPassFailure();
    numVectorized += done->vectorized;
    numScalar += done->scalar;
  }
};

} // namespace
