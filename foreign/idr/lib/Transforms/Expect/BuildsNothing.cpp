// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// builds-nothing: a function builds no value in memory: what it returns or
// holds is its parameters' or static data. Building is what the effect
// system's declaration of an op says: memory acquired for a result, of the
// heap or of the frame, or a write of the contents or beneath them, a
// cell's fields as it is filled among them, a recycled one's included. A
// fresh identity alone (a reference taken, a field read out) is no memory
// built; a call's building is its callee's, stated of the callee.

#include "idr/Transforms/Expect.h"

#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Effects/Whole.h"

#include "mlir/Interfaces/CallInterfaces.h"

using namespace mlir;

namespace idr::expect {

LogicalResult buildsNothing(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn.getFunctionBody().walk([&](Operation *op) {
      if (isa<CallOpInterface>(op))
        return;
      if (!effects::acquires(op) && (effects::own(op).byKind[effects::Kind::Write] &
                                     effects::atOrBelow[effects::ResourceId::Contents])
                                        .empty())
        return;
      fail(op->getLoc(), request.property) << op->getName() << " builds a value in " << where(op);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
