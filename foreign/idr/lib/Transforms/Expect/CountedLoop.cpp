// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// counted-loop: what idr-tail-loops guarantees of a function's loops,
// stated as a property of the loops, not as the ops that happen to show
// it.

#include "idr/Transforms/Expect.h"

#include "mlir/Dialect/SCF/IR/SCF.h"

using namespace mlir;

namespace idr::expect {

// The function (or a clone of it) loops, and every loop it has counts to a
// bound with a step: an scf.for, which says its trip count, and no
// scf.while.
LogicalResult countedLoop(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "counted-loop";
  SmallVector<FunctionOpInterface> functions =
      named(module, function, property);
  if (functions.empty())
    return failure();
  unsigned counted = 0;
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (isa<scf::ForOp>(op))
        ++counted;
      if (isa<scf::WhileOp>(op)) {
        fail(op->getLoc(), property) << "a loop of " << where(op) << " has no trip count";
        held = false;
      }
    });
  if (held && counted == 0) {
    fail(functions.front()->getLoc(), property) << function << " has no loop";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
