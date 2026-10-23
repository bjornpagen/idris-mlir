// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An op of the generating set whose region holds a call on its function's
// own cycle, made its loops as join points: frames split a join region,
// and no other region of the generating set, so the call keeps the cycle's
// depth on the frame stacks and never hides a recursion inside an op they
// cannot take apart.
//
// The loops are the op's own: one recursive join point per dimension of
// its domain, in row-major order, the last dimension fastest, each step
// made by the op's tiling method, the one meaning of a step that
// idr-ordered-loops reads too. So the step's movements are those counting
// already decided for the op: the op on buffers stood through counting,
// and the loops are made on the counted program, where those movements
// exist. A step's region never runs on an empty domain: a dimension of
// size 0 ends its loop before its first turn.

#include "idr/Transforms/StructureLoops.h"

#include "idr/Transforms/Joins.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Arith/Utils/Utils.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;

namespace idr::structure {

namespace {

// An idr.loop at the rewriter's insertion point that takes each index below
// `extent` in turn, from 0 up: its body jumps into its one join region with
// 0, and the region, while its index is below `extent`, runs a turn and
// jumps back with the next index, and otherwise ends the loop. The loop
// gives nothing, since a step on buffers writes memory, and binds no index
// variable. The rewriter is left where a turn's code goes, before the next
// index is made; the index is returned.
Value sweep(RewriterBase &rewriter, Location loc, Value extent) {
  Region turn;
  {
    OpBuilder::InsertionGuard guard(rewriter);
    Type index = rewriter.getIndexType();
    rewriter.createBlock(&turn, turn.end(), ArrayRef<Type>(index), ArrayRef<Location>(loc));
    YieldOp::create(rewriter, loc, ValueRange());
  }
  joins::Member member{&turn, IndexBindersAttr::get(rewriter.getContext(), {}), 0};
  joins::Edge back{0, 0};
  joins::Group group = joins::build(rewriter, loc, TypeRange(), member, back, joins::Ending::Ends);
  Value zero = arith::ConstantIndexOp::create(rewriter, loc, 0);
  JumpOp::create(rewriter, loc, group.targets.tokenFor(0, group.body->getParent()),
                 ValueRange(zero), IndexArgsAttr());

  Region &joined = group.outermost->getRegion(1);
  Value index = cast<JoinPointsOpInterface>(group.outermost).getParameters(joined).front();
  Value token = group.targets.tokenFor(0, &joined);
  rewriter.setInsertionPoint(joined.front().getTerminator());
  Value more = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ult, index, extent);
  auto ahead = scf::IfOp::create(rewriter, loc, more, [&](OpBuilder &b, Location at) {
    Value one = arith::ConstantIndexOp::create(b, at, 1);
    Value next = arith::AddIOp::create(b, at, index, one);
    JumpOp::create(b, at, token, ValueRange(next), IndexArgsAttr());
  });
  rewriter.setInsertionPointToStart(&ahead.getThenRegion().front());
  return index;
}

} // namespace

LogicalResult joinLoops(RewriterBase &rewriter, DestinationStyleOpInterface op) {
  if (!op.hasPureBufferSemantics())
    return op->emitOpError("internal error: is made join-point loops on tensors, which it "
                           "writes in no order");
  OpBuilder::InsertionGuard guard(rewriter);
  Location loc = op.getLoc();
  rewriter.setInsertionPoint(op);
  auto tiling = cast<TilingInterface>(op.getOperation());
  // Every extent is read where the op stood, before any loop: each loop
  // compares against one that dominates it.
  SmallVector<Value> extents =
      llvm::map_to_vector(tiling.getIterationDomain(rewriter), [&](const Range &range) {
        return getValueOrCreateConstantIndexOp(rewriter, loc, range.size);
      });
  SmallVector<Value> indices =
      llvm::map_to_vector(extents, [&](Value extent) { return sweep(rewriter, loc, extent); });
  if (failed(tiling.generateScalarImplementation(rewriter, loc, indices)))
    return failure();
  // The calls the step holds are the op's region's, each an ordinary call
  // there, since no break crosses an op of the generating set; they now
  // stand in a join region's turn, which goes on to its jump back, so each
  // is an ordinary call still.
  rewriter.eraseOp(op);
  return success();
}

} // namespace idr::structure
