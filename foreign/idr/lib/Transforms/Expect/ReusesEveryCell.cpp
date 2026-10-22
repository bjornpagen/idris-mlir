// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// reuses-every-cell: every cell a function takes apart is filled again, not
// freed. A cell taken apart is a reuse token's, and the op that spends a
// token either makes a cell of it or gives its memory back, which its
// declaration says to the effect system as a free of heap memory. A token
// passed on (to a rejoin, a join point, a call) is spent where it arrives.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

LogicalResult reusesEveryCell(const Request<Functions> &request) {
  bool held = true;
  auto isToken = [](Type type) { return isa<TokenType>(unrestricted(type)); };
  for (FunctionOpInterface fn : request.argument.functions)
    fn.getFunctionBody().walk([&](Operation *op) {
      if (isa<CallOpInterface>(op) || llvm::none_of(op->getOperandTypes(), isToken) ||
          !effects::own(op).on(effects::Kind::Free, effects::ResourceId::Heap))
        return;
      fail(op->getLoc(), request.property)
          << op->getName() << " frees the cell a reuse token holds, not reused, in " << where(op);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
