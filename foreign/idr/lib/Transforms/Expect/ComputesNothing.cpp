// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// computes-nothing: a function computes no value, stated as what is left
// of it: what may crash and what ends its blocks. An op that only computes
// and whose value nothing uses is dead code, which the folds and the dead
// code removal take; a guard or a crash is kept for the crash. So that
// nothing else is left is the property, whatever the ops were.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/UB/IR/UBOps.h"

using namespace mlir;

namespace idr::expect {

// Every op left in every copy of @f is a guard, an op that never returns,
// ub.unreachable or a block's terminator.
LogicalResult computesNothing(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    for (Block &block : fn.getFunctionBody())
      for (Operation &op : block) {
        if (isa<GuardOpInterface, ub::UnreachableOp>(op) || op.hasTrait<NoReturn>() ||
            op.hasTrait<OpTrait::IsTerminator>())
          continue;
        fail(op.getLoc(), request.property) << op.getName() << " is left in " << where(fn);
        held = false;
      }
  return success(held);
}

} // namespace idr::expect
