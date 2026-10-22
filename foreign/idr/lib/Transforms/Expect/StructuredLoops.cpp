// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// structured-loops: what the arrays stage guarantees by the lowering,
// stated as a property of what is left: no op of the generating set (the
// one rule of it, Arrays.h), every one structured or turned into its loops
// before the program is taken apart.

#include "Checks.h"

#include "idr/IR/Arrays.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"

using namespace mlir;

namespace idr::expect {

// In the function the argument names or anywhere, no op of the generating
// set is left, and there is at least one structured op, so
// the property cannot hold of a module that never had an array.
LogicalResult structuredLoops(const Request<Roots> &request) {
  SmallVector<Operation *> roots = request.argument.roots(request.module);
  bool held = true, structured = false;
  for (Operation *root : roots)
    root->walk([&](Operation *op) {
      if (isa_and_nonnull<linalg::LinalgDialect>(op->getDialect()))
        structured = true;
      if (!arrays::isGenerating(op))
        return;
      fail(op->getLoc(), request.property) << op->getName() << " is left unlowered in "
                                           << where(op);
      held = false;
    });
  if (!structured) {
    fail(roots.front()->getLoc(), request.property) << "no structured op"
                                                    << request.argument.in();
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
