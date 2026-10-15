// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// counts-nothing: a function counts no reference.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;

namespace idr::expect {

// The function the argument names counts no reference: no idr.dup, no
// idr.drop.
LogicalResult countsNothing(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "counts-nothing";
  SmallVector<FunctionOpInterface> functions =
      named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](Operation *op) {
      if (!isa<DupOp, DropOp>(op))
        return;
      // Static data holds no count: a reference to it costs nothing.
      if (auto dup = dyn_cast<DupOp>(op); dup && matchPattern(dup.getValue(), m_Constant()))
        return;
      fail(op->getLoc(), property) << op->getName() << " in " << where(op);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
