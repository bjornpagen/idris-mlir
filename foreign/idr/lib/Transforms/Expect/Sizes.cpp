// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// largest-function: a bound on the size of every function, counted as the
// inline decisions count it, so that a test states what the per-caller
// cap keeps: inlining stops at the cap and leaves a call.

#include "idr/Transforms/Expect.h"

#include "idr/Analysis/Inline.h"
#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// No function holds more operations than the bound the argument gives.
LogicalResult largestFunction(const Request<Bound> &request) {
  uint64_t bound = request.argument.bound;
  bool held = true;
  for (FunctionOpInterface each : functionsOf(request.module)) {
    auto fn = dyn_cast<FuncOp>(each.getOperation());
    if (!fn)
      continue;
    // A size counts operations, so it is never negative.
    auto size = static_cast<uint64_t>(inlineSize(fn));
    if (size <= bound)
      continue;
    fail(fn.getLoc(), request.property) << where(fn) << " holds " << size
                                        << " operations, more than " << bound;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
