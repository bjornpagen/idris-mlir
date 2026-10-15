// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// fused: no array is made only to be read by the next loop. A structured
// op whose one consumer is another structured op left an intermediate
// array that fusion would have removed; that none is left is the property.

#include "idr/Transforms/Expect.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"

using namespace mlir;

namespace idr::expect {

// In the function the argument names, no result of a structured op that
// has one use is used by another structured op, and there is one.
LogicalResult fused(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "fused";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true, structured = false;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](linalg::LinalgOp producer) {
      structured = true;
      for (Value result : producer->getResults()) {
        if (!result.hasOneUse() || !isa<linalg::LinalgOp>(*result.getUsers().begin()))
          continue;
        fail(producer->getLoc(), property) << producer->getName() << " in " << where(producer)
                                           << " makes an array only its one consumer reads";
        held = false;
      }
    });
  if (!structured) {
    fail(functions.front()->getLoc(), property) << "no structured op in " << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
