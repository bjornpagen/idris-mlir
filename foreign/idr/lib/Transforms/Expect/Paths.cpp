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
LogicalResult loops(ModuleOp module, AnalysisManager &, StringRef argument) {
  constexpr StringRef property = "loops";
  StringRef function = argument;
  std::optional<unsigned> wanted;
  if (argument.contains(':')) {
    StringRef count;
    std::tie(function, count) = splitAt(module, argument, property);
    if (function.empty())
      return failure();
    unsigned n = 0;
    if (count.getAsInteger(10, n))
      return fail(module.getLoc(), property) << "name the count, as loops=@f:<n>";
    wanted = n;
  }
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions) {
    unsigned found = 0;
    fn->walk([&](LoopLikeOpInterface) { ++found; });
    if (wanted ? found == *wanted : found > 0)
      continue;
    InFlightDiagnostic error = fail(fn->getLoc(), property) << where(fn) << " has " << found
                                                            << " loops";
    if (wanted)
      error << ", not " << *wanted;
    held = false;
  }
  return success(held);
}

// Every copy of @f runs one path: no op of it chooses among or repeats
// its regions, and no block of it ends in a choice of successors.
LogicalResult straightLine(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "straight-line";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (!isa<RegionBranchOpInterface>(op) && op->getNumSuccessors() < 2)
        return;
      fail(op->getLoc(), property) << op->getName() << " branches in " << where(op);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
