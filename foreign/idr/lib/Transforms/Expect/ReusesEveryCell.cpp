// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// reuses-every-cell: every cell a take yields is recycled, not freed. A
// take is of a value with a cell, a constructor with fields: an atom, which
// has none, is unpacked, and yields no cell.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// In the function the argument names, every cell a take yields is
// recycled: no idr.drop of a take's token frees one.
LogicalResult reusesEveryCell(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn->walk([&](DropOp drop) {
      auto take = drop.getValue().getDefiningOp<TakeOp>();
      if (!take || drop.getValue() != take.getToken())
        return;
      fail(drop.getLoc(), request.property)
          << "the cell of @" << take.getDataType().getCtor(take.getTag()).name.getValue()
          << " is freed, not reused, in " << where(drop);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
