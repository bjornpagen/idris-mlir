// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// structured-loops: what idr-structure-loops guarantees, stated as a
// property of what is left: no op of the generating set it lowers. Which
// op it lowers is its own test, asked here, so the rule is held once.

#include "idr/Transforms/Expect.h"

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"

using namespace mlir;

namespace idr::expect {

// In the function the argument names or anywhere, no op is left that
// idr-structure-loops lowers, and there is at least one structured op, so
// the property cannot hold of a module that never had an array.
LogicalResult structuredLoops(const Request<Roots> &request) {
  SmallVector<Operation *> roots = request.argument.roots(request.module);
  bool held = true, structured = false;
  for (Operation *root : roots)
    root->walk([&](Operation *op) {
      if (isa_and_nonnull<linalg::LinalgDialect>(op->getDialect()))
        structured = true;
      if (!structure::structurable(op))
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
