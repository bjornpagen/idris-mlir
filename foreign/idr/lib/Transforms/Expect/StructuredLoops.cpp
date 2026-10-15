// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// structured-loops: what idr-structure-loops guarantees, stated as a
// property of the loops left: none of them is one it structures. Which
// loop it structures is its own test, asked here, so the rule is held
// once: a pure float fold, for one, stays an ordered loop by design.

#include "idr/Transforms/Expect.h"

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Interfaces/LoopLikeInterface.h"

using namespace mlir;

namespace idr::expect {

// In the function the argument names or anywhere, no loop is left that
// idr-structure-loops would turn into a structured op, and there is at
// least one structured op, so the property cannot hold of a module that
// never had an array loop.
LogicalResult structuredLoops(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "structured-loops";
  SmallVector<Operation *> roots = rootsOf(module, function, property);
  if (roots.empty())
    return failure();
  bool held = true, structured = false;
  for (Operation *root : roots)
    root->walk([&](Operation *op) {
      if (isa_and_nonnull<linalg::LinalgDialect>(op->getDialect()))
        structured = true;
      if (!isa<LoopLikeOpInterface>(op) || !structure::structurable(op))
        return;
      fail(op->getLoc(), property) << "a loop over an array with a body that only computes is still "
                                   << op->getName() << " in " << where(op);
      held = false;
    });
  if (!structured) {
    fail(roots.front()->getLoc(), property) << "no structured op"
                                            << (function.empty() ? "" : " in ") << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
