// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// reuses-in-place: a function builds in recycled cells. Once memory is
// explicit, a value with a cell is built by filling a cell, a value of cell
// type, and where the cell came from is the op that made it: one made from
// a reuse token, an operand of token type, is that token's cell, unless the
// effect system's declaration says it acquires heap memory for it, as for a
// token that may be null; any other is fresh, or a lifetime's, and no
// recycled cell either.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

// The function the argument names and its clones together: at least one
// of them fills a recycled cell, and none fills another.
LogicalResult reusesInPlace(const Request<Functions> &request) {
  ArrayRef<FunctionOpInterface> functions = request.argument.functions;
  bool held = true, recycled = false;
  auto isToken = [](Type type) { return isa<TokenType>(unrestricted(type)); };
  for (FunctionOpInterface fn : functions)
    fn.getFunctionBody().walk([&](Operation *maker) {
      bool fromToken = llvm::any_of(maker->getOperandTypes(), isToken);
      for (OpResult cell : maker->getResults()) {
        auto type = dyn_cast<CellType>(cell.getType());
        if (!type)
          continue;
        if (fromToken && !effects::allocates(maker, cell)) {
          recycled = true;
          continue;
        }
        fail(maker->getLoc(), request.property)
            << "a cell of @" << type.getData().ctor(type.getTag()).label << " is "
            << (fromToken ? "new memory where its token is null" : "not a recycled one") << " in "
            << where(maker);
        held = false;
      }
    });
  if (!recycled) {
    fail(functions.front()->getLoc(), request.property)
        << "nothing is built in a reused cell in @" << request.argument.name;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
