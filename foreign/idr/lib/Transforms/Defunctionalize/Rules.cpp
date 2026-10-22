// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The e-graph's rule over a memo cell's exchange: what a force of a cell
// built for that force alone is. Its cell has one use, the exchange, so the
// state it enters and the value it takes are seen by nobody: the label runs
// on the captures as a call would, and the cell goes with the exchange.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace idr::egraph {

std::optional<Edit> ForceFreshCell::decide(MemoRunOp run, const OperandFacts &facts) {
  Operation *built = facts.origin(run.getCell());
  if (!built || !isa<DataConOp>(built) || !run.getCell().hasOneUse())
    return std::nullopt;
  return Edit(Rewrite{});
}

// The region's block runs before the exchange, its captures the
// constructor's fields held as the region binds them, and its results are
// what the yield gives after the forced value.
void ForceFreshCell::rewrite(MemoRunOp run, Rewrite, RewriterBase &rewriter) {
  auto built = run.getCell().getDefiningOp<DataConOp>();
  Block &body = run.getRegion().front();
  auto end = cast<MemoYieldOp>(body.getTerminator());
  rewriter.setInsertionPoint(run);
  SmallVector<Value> captures;
  for (auto [field, capture] : llvm::zip_equal(built.getFields(), body.getArguments()))
    captures.push_back(heldAs(rewriter, run.getLoc(), field, capture.getType()));
  SmallVector<Value> results(end.getValues().drop_front());
  rewriter.inlineBlockBefore(&body, run, captures);
  rewriter.replaceOp(run, results);
  rewriter.eraseOp(end);
}

} // namespace idr::egraph
