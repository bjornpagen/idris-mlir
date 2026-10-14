// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// no-closures: after defunctionalization, or where a test says every
// closure is gone, none is built, applied or kept as a constant.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// No closure is built, applied or kept as a constant.
LogicalResult noClosures(ModuleOp module, AnalysisManager &, StringRef) {
  bool held = true;
  module.walk([&](Operation *op) {
    StringRef found;
    if (isa<ClosureOp>(op))
      found = "a closure is built";
    else if (isa<ApplyOp>(op))
      found = "a closure is applied";
    else if (auto constant = dyn_cast<ConstantOp>(op);
             constant && isa<ClosureAttr>(constant.getValue()) && !isa<LazyType>(constant.getType()))
      found = "a closure is a constant";
    else
      return;
    fail(op->getLoc(), "no-closures") << found << " in " << where(op);
    held = false;
  });
  return success(held);
}

} // namespace idr::expect
