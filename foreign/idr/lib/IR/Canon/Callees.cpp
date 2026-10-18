// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops a pattern that moves an op across others tells the driver to try
// again (canon::retryBetween): sinking, case-of-case and an element's
// update ask of the ops between two whether they only compute, which no
// operand or user links.

#include "idr/IR/Canon.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

// An op told to have changed in place, with nothing changed, is one the
// driver puts back on its worklist, which is all this asks of it.
void idr::canon::retryBetween(PatternRewriter &rewriter,
                              llvm::iterator_range<Block::iterator> ops) {
  auto ofMatch = [](Value operand) {
    return isa_and_nonnull<MatchOpInterface>(operand.getDefiningOp());
  };
  for (Operation &op : ops)
    if (isa<MatchOpInterface, ArraySetOp>(op) || llvm::any_of(op.getOperands(), ofMatch))
      rewriter.modifyOpInPlace(&op, [] {});
}
