// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// loops and straight-line: the shape of a function's control, stated as
// how many loops it has and whether it branches at all, not as the ops
// that show either. A loop is an op that repeats its body (scf.for,
// scf.while, an idr loop); a branch is an op that chooses among its
// regions or its successors.

#include "idr/Transforms/Expect.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/LoopLikeInterface.h"

using namespace mlir;

namespace idr::expect {

// Every copy of @f has a loop, or, with `@f:<n>`, exactly n loops.
LogicalResult loops(const Request<Loops> &request) {
  std::optional<unsigned> wanted = request.argument.count;
  bool held = true;
  for (FunctionOpInterface fn : request.argument.function.functions) {
    unsigned found = 0;
    fn->walk([&](LoopLikeOpInterface) { ++found; });
    if (wanted ? found == *wanted : found > 0)
      continue;
    InFlightDiagnostic error = fail(fn->getLoc(), request.property)
                               << where(fn) << " has " << found << " loops";
    if (wanted)
      error << ", not " << *wanted;
    held = false;
  }
  return success(held);
}

// Every copy of @f runs one path: no op of it chooses among or repeats
// its regions, and no block of it ends in a choice of successors.
LogicalResult straightLine(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn->walk([&](Operation *op) {
      if (!isa<RegionBranchOpInterface>(op) && op->getNumSuccessors() < 2)
        return;
      fail(op->getLoc(), request.property) << op->getName() << " branches in " << where(op);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
