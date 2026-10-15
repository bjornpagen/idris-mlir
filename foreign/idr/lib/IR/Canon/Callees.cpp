// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the call-aware patterns (canon::CalleePattern) share: their binding
// to a program's table, which a canonicalizer does to the patterns it
// collected before it freezes them, and the ops a move across others tells
// the driver to try again.

#include "idr/IR/Canon.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

#include <memory>

using namespace mlir;

void idr::canon::bindCallees(RewritePatternSet &patterns, const CalleeEffects *callees) {
  // Every pattern with the label is a CalleePattern: its constructor alone
  // adds it.
  for (std::unique_ptr<RewritePattern> &pattern : patterns.getNativePatterns())
    if (llvm::is_contained(pattern->getDebugLabels(), CalleePattern::kLabel))
      pattern = static_cast<const CalleePattern &>(*pattern).withCallees(callees);
}

// An op told to have changed in place, with nothing changed, is one the
// driver puts back on its worklist, which is all this asks of it.
void idr::canon::CalleePattern::retryBetween(PatternRewriter &rewriter,
                                             llvm::iterator_range<Block::iterator> ops) {
  auto ofMatch = [](Value operand) {
    return isa_and_nonnull<MatchOp, MatchLitOp>(operand.getDefiningOp());
  };
  for (Operation &op : ops)
    if (isa<MatchOp, MatchLitOp, ArraySetOp>(op) || llvm::any_of(op.getOperands(), ofMatch))
      rewriter.modifyOpInPlace(&op, [] {});
}
