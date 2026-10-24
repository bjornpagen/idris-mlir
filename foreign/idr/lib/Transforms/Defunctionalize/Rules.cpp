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
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::egraph {

namespace {

// The idr.data.con that built the cell an exchange forces, read through
// each cast into or out of a linear position the cell passed (as the
// e-graph reads it), where the cell is built for that force alone: each
// value from the constructor's result to the exchange's operand has one
// use. Null otherwise. The decision and the rewrite read it alike, so the
// rewrite finds the op the decision found.
DataConOp freshCell(MemoRunOp run) {
  SmallVector<Value, 4> passed = linearPositions(run.getCell());
  if (!llvm::all_of(passed, [](Value value) { return value.hasOneUse(); }))
    return {};
  return passed.back().getDefiningOp<DataConOp>();
}

} // namespace

std::optional<Edit> ForceFreshCell::decide(MemoRunOp run, const OperandFacts &) {
  if (!freshCell(run))
    return std::nullopt;
  return Edit(Rewrite{});
}

// The region's block runs before the exchange, its captures the
// constructor's fields held as the region binds them, and its results are
// what the yield gives; the value it moved into the cell goes with the cell.
// Each call the region made, an ordinary call there since no break crosses
// an exchange, now stands where the exchange stood, an op that holds no
// fact of where it stood: the e-graph's turn after the rewrite writes the
// function back, and every call's fact with it.
void ForceFreshCell::rewrite(MemoRunOp run, const Rewrite &, RewriterBase &rewriter) {
  DataConOp built = freshCell(run);
  if (!built)
    return;
  Block &body = run.getRegion().front();
  auto end = cast<MemoYieldOp>(body.getTerminator());
  rewriter.setInsertionPoint(run);
  SmallVector<Value> captures;
  for (auto [field, capture] : llvm::zip_equal(built.getFields(), body.getArguments()))
    captures.push_back(heldAs(rewriter, run.getLoc(), field, capture.getType()));
  SmallVector<Value> results(end.getResults());
  rewriter.inlineBlockBefore(&body, run, captures);
  rewriter.replaceOp(run, results);
  rewriter.eraseOp(end);
}

} // namespace idr::egraph
