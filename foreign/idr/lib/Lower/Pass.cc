// idr-lower: idr to func, arith, math, scf, ub and llvm, as idr.lower's
// lowerModule does it.

#include "idr/Idr.h"

// Dialects idr-lower depends on that idr/Idr.h does not declare.
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"

namespace idr {
#define GEN_PASS_DEF_IDRLOWER
#include "idr/Passes.h.inc"
} // namespace idr

import idr.lower;

namespace {

struct Lower : idr::impl::IdrLowerBase<Lower> {
  using IdrLowerBase::IdrLowerBase;

  void runOnOperation() override {
    if (mlir::failed(idr::lower::lowerModule(getOperation())))
      signalPassFailure();
  }
};

} // namespace
