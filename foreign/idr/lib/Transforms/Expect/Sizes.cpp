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
LogicalResult largestFunction(ModuleOp module, AnalysisManager &, StringRef argument) {
  constexpr StringRef property = "largest-function";
  int64_t bound = 0;
  if (argument.getAsInteger(10, bound) || bound < 0)
    return fail(module.getLoc(), property) << "name the bound, as largest-function=<n>";
  bool held = true;
  for (FunctionOpInterface each : functionsOf(module)) {
    auto fn = dyn_cast<FuncOp>(each.getOperation());
    if (!fn)
      continue;
    int64_t size = inlineSize(fn);
    if (size <= bound)
      continue;
    fail(fn.getLoc(), property) << where(fn) << " holds " << size << " operations, more than " << bound;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
