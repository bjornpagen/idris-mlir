// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// counts-nothing: a function counts no reference. What counts is what the
// effect system's declaration of an op says reads or writes a count: a
// reference taken, a release or a take of a value whose type proves nothing
// of its sharing, the run-time test of sharing. A release of a value typed
// unique frees it and reads no count, so it counts nothing; a call's
// counts are its callee's, stated of the callee.

#include "Checks.h"

#include "idr/IR/Effects/Query.h"

#include "mlir/Interfaces/CallInterfaces.h"

using namespace mlir;

namespace idr::expect {

LogicalResult countsNothing(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn.getFunctionBody().walk([&](Operation *op) {
      if (isa<CallOpInterface>(op))
        return;
      effects::EffectSet own = effects::own(op);
      if (!own.on(effects::Kind::Read, effects::ResourceId::Count) &&
          !own.on(effects::Kind::Write, effects::ResourceId::Count))
        return;
      fail(op->getLoc(), request.property) << op->getName() << " counts a reference in " << where(op);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
