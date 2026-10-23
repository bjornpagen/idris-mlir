// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An element's update whose region calls into its function's own cycle,
// split where frames can take its code apart: the element is taken out of
// its place, the region's code runs inline, and the rebuilt element is put
// back, in mutable memory or a value array's buffer alike. One form covers
// a call written in the region and one fusion moved there.
//
// The take and the put-back are the update's own exchange, which counting
// already decided: the element moves out with the reference its place held
// and the rebuilt one moves back. Between them nothing reads the place: the
// region touches no memory written in place (its verifier), a value
// array's buffer an update writes is the one One-Shot proved its write in
// place on, and a boxed element a copy of the array shares is copied before
// it is taken (Elements.h, takeOut), so the copy keeps its element.

#include "idr/Transforms/StructureLoops.h"

using namespace mlir;

namespace idr::structure {

void splitUpdate(RewriterBase &rewriter, ArrayUpdateOp update) {
  OpBuilder::InsertionGuard guard(rewriter);
  Location loc = update.getLoc();
  Value array = update.getArray();
  Block &body = update.getRegion().front();
  Operation *end = body.getTerminator();
  rewriter.setInsertionPoint(update);
  auto taken = ArrayTakeOp::create(rewriter, loc, body.getArgument(0).getType(), array,
                                   update.getIndices());
  // The calls the region held, each an ordinary call there, since no break
  // crosses an update, now stand in the update's block between the take and
  // the put-back after them, or before the end of a region that never
  // returns: an ordinary call still.
  rewriter.inlineBlockBefore(&body, update, ValueRange(taken.getValue()));
  if (auto yield = dyn_cast<ArrayUpdateYieldOp>(end)) {
    rewriter.setInsertionPoint(update);
    arrays::putBackAt(rewriter, loc, yield.getElement(), array, update.getIndices());
    rewriter.replaceOp(update, yield.getOuts());
    rewriter.eraseOp(yield);
    return;
  }
  // A region that never returns ends the block where it ends: what followed
  // the update never runs, the block's own terminator among it.
  Block *block = end->getBlock();
  while (&block->back() != end)
    rewriter.eraseOp(&block->back());
}

} // namespace idr::structure
