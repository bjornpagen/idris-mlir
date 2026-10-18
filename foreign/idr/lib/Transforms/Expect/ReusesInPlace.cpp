// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// reuses-in-place: what reference counting left in a function, stated as
// the property a test wants of it: it builds in recycled cells. Once cells
// are explicit, a box is built by the idr.cell.init that writes its cell,
// and where the cell came from is the op that gave it: a cell of a take's
// token (idr.cell.recycle), a fresh one on the heap (idr.cell.new), or one
// in the frame (idr.cell.stack), which is no recycled cell either.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// The function the argument names and its clones together: at least one
// of them builds in a recycled cell, and none builds in a fresh cell.
LogicalResult reusesInPlace(const Request<Functions> &request) {
  ArrayRef<FunctionOpInterface> functions = request.argument.functions;
  bool held = true, recycled = false;
  for (FunctionOpInterface fn : functions)
    fn->walk([&](CellInitOp init) {
      if (isa_and_nonnull<CellRecycleOp>(init.getCell().getDefiningOp())) {
        recycled = true;
        return;
      }
      fail(init.getLoc(), request.property)
          << "a box of @" << init.getDataType().getCtor(init.getTag()).name.getValue()
          << " gets a fresh cell in " << where(init);
      held = false;
    });
  if (!recycled) {
    fail(functions.front()->getLoc(), request.property)
        << "nothing is built in a reused cell in @" << request.argument.name;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
