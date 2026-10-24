// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The account an active call keeps, in the checked runtime, of the bytes it
// holds that it no longer needs, against the bound counting computed for its
// function from types (its frame bound): opened where the call begins, told
// each point where what it holds rises or falls, and closed where it returns
// and before each call in tail position, which ends it as a jump. The points
// are the ones the bound was computed from, read off the same walk, so the
// account states no rule of its own and needs no test of its own: a token
// that may be null counts at its cell's size where it is made and where it
// is given up, as the bound counts it. A function whose bound is zero holds
// nothing at any allocation, so it keeps no account and tells none. An
// allocation made while a call holds more than its bound ends the run as
// the runtime's internal error.
//
// The calls go into every program: the shipped runtime's entries are empty
// and inline to nothing once its bitcode joins the program, so the runtime a
// program is built with decides, and no test in the program does. They go
// in before the function becomes LLVM's, while its bound is still its own,
// as LLVM ops among its ops; where the call ends is one rooted pattern per
// op that ends it, applied once per op, the op left as it is.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/Func.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"
#include "idr/Transforms/Counting/Bound.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A pattern that tells the account the call ends at its op.
template <typename OpT>
struct Tells : OpRewritePattern<OpT> {
  Tells(MLIRContext *ctx, const Runtime &runtime) : OpRewritePattern<OpT>(ctx), runtime(runtime) {}

  void leaves(OpBuilder &b, Location loc) const {
    runtime.call(b, loc, idr::runtime::helper::peakLeave, ValueRange{});
  }

  const Runtime &runtime;
};

// The call returns.
struct TellReturn : Tells<ReturnOp> {
  using Tells::Tells;
  LogicalResult matchAndRewrite(ReturnOp op, PatternRewriter &rewriter) const override {
    rewriter.setInsertionPoint(op);
    leaves(rewriter, op.getLoc());
    return success();
  }
};

// A tail call, which ends the call as a jump; any other call returns to it.
struct TellTailCall : Tells<TailCallOp> {
  using Tells::Tells;
  LogicalResult matchAndRewrite(TailCallOp op, PatternRewriter &rewriter) const override {
    rewriter.setInsertionPoint(op);
    leaves(rewriter, op.getLoc());
    return success();
  }
};

} // namespace

FrozenRewritePatternSet accountPatterns(MLIRContext *ctx, const Runtime &runtime) {
  RewritePatternSet tells(ctx);
  tells.add<TellReturn, TellTailCall>(ctx, runtime);
  return FrozenRewritePatternSet(std::move(tells));
}

void keepAccount(FuncOp fn, const FrozenRewritePatternSet &tells, const Layouts &layouts,
                 const Runtime &runtime) {
  int64_t bound = fn.getFrameBound();
  // A call that holds nothing at any allocation keeps no account.
  if (bound == 0)
    return;
  // The points are found on the function as it stands, before anything is
  // put into it. Each names the op it goes before, which nothing put there
  // moves, so the points at one place keep the walk's order, and a point
  // before a return or a tail call comes before the call ends.
  for (const counting::HoldPoint &point : counting::holdPoints(fn, layouts)) {
    OpBuilder b(point.where.block, point.where.next);
    Location loc = point.where.next->getLoc();
    // A point's bytes are counted in the bound's own width, a signed word:
    // a count of bytes of a 64-bit address space fits it, and so does its
    // negation, the fall.
    auto bytes = static_cast<int64_t>(point.bytes);
    int64_t change = point.direction == counting::Direction::Rises ? bytes : -bytes;
    runtime.call(b, loc, idr::runtime::helper::peakHeld, i64Constant(b, loc, change));
  }
  walkAndApplyPatterns(fn, tells);
  Location loc = fn.getLoc();
  OpBuilder b = OpBuilder::atBlockBegin(&fn.getBody().front());
  runtime.call(b, loc, idr::runtime::helper::peakEnter,
               ValueRange{staticAddress(b, loc, runtime.statics().account(fn.getSymNameAttr())),
                          i64Constant(b, loc, bound)});
}

} // namespace idr::conversion
