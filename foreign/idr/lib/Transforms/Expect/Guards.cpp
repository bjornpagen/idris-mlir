// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// no-guards: which guards a function keeps. A proof is the guard's
// absence: a guard folds to its operand where the operand shows its
// condition holds, and lowering checks those left.

#include "Checks.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// The function the argument names keeps no guard of any kind: every
// condition its partial primitives need is proven where it runs.
LogicalResult noGuards(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn->walk([&](GuardOpInterface guard) {
      fail(guard->getLoc(), request.property)
          << guard->getName() << " is left in " << where(guard);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
