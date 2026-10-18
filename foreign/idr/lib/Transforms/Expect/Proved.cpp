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

LogicalResult provedIs(const Request<Functions> &request, bool wanted) {
  bool held = true;
  for (FunctionOpInterface each : request.argument.functions) {
    auto fn = dyn_cast<FuncOp>(each.getOperation());
    if (fn && fn.getTotal() == wanted)
      continue;
    fail(each->getLoc(), request.property)
        << where(each) << (fn && fn.getTotal() ? " holds" : " does not hold")
        << " Idris's proof of termination";
    held = false;
  }
  return success(held);
}

} // namespace

// Every copy of @f is an idr.func that holds `total`, or that does not.
LogicalResult total(const Request<Functions> &request) { return provedIs(request, true); }
LogicalResult notTotal(const Request<Functions> &request) { return provedIs(request, false); }

} // namespace idr::expect
