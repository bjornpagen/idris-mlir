// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// effects: what idr-effects found a function may do, stated as the set the
// function holds, the one copy every call reads, not as the ops of a pass
// that happens to act on it. A function no pass has solved holds the
// default, that it may do anything.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// Every copy of @f is an idr.func whose effects are exactly the set
// written, of io, crash and diverge.
LogicalResult solvedEffects(const Request<EffectsOf> &request) {
  Effect wanted = request.argument.effects;
  bool held = true;
  for (FunctionOpInterface each : request.argument.function.functions) {
    auto fn = dyn_cast<FuncOp>(each.getOperation());
    if (!fn) {
      fail(each->getLoc(), request.property)
          << where(each) << " is no idr.func, which holds its effects";
      held = false;
      continue;
    }
    Effect found = fn.getEffects();
    if (found == wanted)
      continue;
    fail(fn.getLoc(), request.property) << where(fn) << " may do " << stringifyEffect(found)
                                        << ", not " << stringifyEffect(wanted);
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
