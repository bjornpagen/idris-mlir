// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// folds-balanced: the folders call the runtime natively, and every owned
// reference they take from it they release, so no fold leaves a cell live.
// What each fold left is counted on the context, so the check holds
// whatever threads folded.

#include "idr/Transforms/Expect.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::expect {

// The folders released every reference they took from the runtime: no
// fold, on any thread, left a cell live. The idr dialect holds the count;
// a context that never loaded it ran no folder of ours (a module of
// upstream's dialects alone, which the contracts check too).
LogicalResult foldsBalanced(const Request<Nothing> &request) {
  ModuleOp module = request.module;
  const auto *idr = module->getContext()->getLoadedDialect<IdrDialect>();
  int64_t left = idr ? idr->foldLeakCount() : 0;
  if (left == 0)
    return success();
  fail(module.getLoc(), request.property) << left << " cells the folders left live";
  return failure();
}

} // namespace idr::expect
