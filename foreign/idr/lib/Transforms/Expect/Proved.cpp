// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// total and not-total: whether a function keeps Idris's proof that every
// loop of its own body ends, stated as the fact the function holds: a pass
// that takes in a body without that proof (inlining, contification) must
// drop it, and one that takes in a proved body keeps it.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

namespace {

LogicalResult provedIs(ModuleOp module, StringRef function, bool wanted, StringRef property) {
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface each : functions) {
    auto fn = dyn_cast<FuncOp>(each.getOperation());
    if (fn && fn.getTotal() == wanted)
      continue;
    fail(each->getLoc(), property) << where(each)
                                   << (fn && fn.getTotal() ? " holds" : " does not hold")
                                   << " Idris's proof of termination";
    held = false;
  }
  return success(held);
}

} // namespace

// Every copy of @f is an idr.func that holds `total`, or that does not.
LogicalResult total(ModuleOp module, AnalysisManager &, StringRef function) {
  return provedIs(module, function, true, "total");
}
LogicalResult notTotal(ModuleOp module, AnalysisManager &, StringRef function) {
  return provedIs(module, function, false, "not-total");
}

} // namespace idr::expect
