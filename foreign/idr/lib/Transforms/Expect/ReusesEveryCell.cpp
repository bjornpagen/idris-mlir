// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// reuses-every-cell: every cell a take yields for a constructor with fields
// is reused, not freed.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// In the function the argument names, every cell a take yields for a
// constructor with fields is reused: no idr.drop frees one. The fields are
// the take's data type's, read from its body.
LogicalResult reusesEveryCell(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "reuses-every-cell";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](DropOp drop) {
      auto take = drop.getValue().getDefiningOp<TakeOp>();
      if (!take || drop.getValue() != take.getToken())
        return;
      // A constructor without fields is a static cell, never the program's
      // to reuse.
      if (take.getDataType().getCtor(take.getTag()).fields.empty())
        return;
      fail(drop.getLoc(), property) << "the cell of " << take.getCtor() << " is freed, not reused, in "
                                    << where(drop);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
