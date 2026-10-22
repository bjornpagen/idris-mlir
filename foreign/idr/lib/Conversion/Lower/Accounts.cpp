// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The account an active call keeps, in the checked runtime, of the bytes it
// holds that it no longer needs, against the bound counting computed for its
// function from types (its frame bound): opened where the call begins, told
// each reuse token the call takes and each it gives up, and closed where it
// returns and before each call in tail position, which ends it as a jump. A
// function whose bound is zero holds nothing at any allocation, so it keeps
// no account and tells none. An allocation made while a call holds more than
// its bound ends the run as the runtime's internal error.
//
// The calls go into every program: the shipped runtime's entries are empty
// and inline to nothing once its bitcode joins the program, so the runtime a
// program is built with decides, and no test in the program does. They go
// in before the function becomes LLVM's, while its bound is still its own,
// as LLVM ops among its ops: one rooted pattern per op that tells, applied
// once per op, the op left as it is.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The bytes of the cell a reuse token of type `token` holds: every source of
// a token is a cell of one size, so its first sizes it.
int64_t tokenBytes(const Layouts &layouts, Type token) {
  auto source = cast<DataType>(cast<TokenType>(unrestricted(token)).getSources().front());
  return static_cast<int64_t>(layouts.cells(source).cell(*source.singleTag()).size);
}

// A pattern that tells the account what its op does to what the call holds.
template <typename OpT>
struct Tells : OpRewritePattern<OpT> {
  Tells(MLIRContext *ctx, const Layouts &layouts, const Runtime &runtime)
      : OpRewritePattern<OpT>(ctx), layouts(layouts), runtime(runtime) {}

  // The call holds `change` more bytes.
  void held(OpBuilder &b, Location loc, Value change) const {
    runtime.call(b, loc, idr::runtime::helper::peakHeld, change);
  }

  // A token taken, which holds its cell: the cell's bytes.
  void takes(OpBuilder &b, Location loc, Type token) const {
    held(b, loc, i64Constant(b, loc, tokenBytes(layouts, token)));
  }

  // A token given up, built into or freed: its cell's bytes, where its grade
  // says it holds its cell; otherwise only where it is not null, which only
  // the run knows.
  void givesUp(OpBuilder &b, Location loc, Value token) const {
    Value fewer = i64Constant(b, loc, -tokenBytes(layouts, token.getType()));
    if (claims(token.getType(), Unique::Deep))
      return held(b, loc, fewer);
    Type ptr = ptrType(b.getContext());
    Value cell = UnrealizedConversionCastOp::create(b, loc, ptr, token).getResult(0);
    Value empty = LLVM::ICmpOp::create(b, loc, LLVM::ICmpPredicate::eq, cell,
                                       LLVM::ZeroOp::create(b, loc, ptr));
    held(b, loc, LLVM::SelectOp::create(b, loc, empty, i64Constant(b, loc, 0), fewer));
  }

  // The call ends.
  void leaves(OpBuilder &b, Location loc) const {
    runtime.call(b, loc, idr::runtime::helper::peakLeave, ValueRange{});
  }

  const Layouts &layouts;
  const Runtime &runtime;
};

// A take's token, held from the take on.
struct TellTake : Tells<CountTakeOp> {
  using Tells::Tells;
  LogicalResult matchAndRewrite(CountTakeOp op, PatternRewriter &rewriter) const override {
    rewriter.setInsertionPointAfter(op);
    takes(rewriter, op.getLoc(), op.getToken().getType());
    return success();
  }
};

// The token of a match on uniqueness, held from the start of its unique
// region, where the count was found to be 1.
struct TellUnique : Tells<CountMatchUniqueOp> {
  using Tells::Tells;
  LogicalResult matchAndRewrite(CountMatchUniqueOp op, PatternRewriter &rewriter) const override {
    Block &unique = op.getUnique().front();
    rewriter.setInsertionPointToStart(&unique);
    takes(rewriter, op.getLoc(), unique.getArgument(0).getType());
    return success();
  }
};

// A token built into a new constructor.
struct TellRecycle : Tells<CellRecycleOp> {
  using Tells::Tells;
  LogicalResult matchAndRewrite(CellRecycleOp op, PatternRewriter &rewriter) const override {
    rewriter.setInsertionPoint(op);
    givesUp(rewriter, op.getLoc(), op.getToken());
    return success();
  }
};

// A token freed.
struct TellFree : Tells<TokenFreeOp> {
  using Tells::Tells;
  LogicalResult matchAndRewrite(TokenFreeOp op, PatternRewriter &rewriter) const override {
    rewriter.setInsertionPoint(op);
    givesUp(rewriter, op.getLoc(), op.getToken());
    return success();
  }
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

// A call in tail position, which ends the call as a jump; any other call
// returns to it.
struct TellTailCall : Tells<CallOp> {
  using Tells::Tells;
  LogicalResult matchAndRewrite(CallOp op, PatternRewriter &rewriter) const override {
    switch (op.getTailKind()) {
    case TailKind::tail:
      break;
    case TailKind::nontail:
    case TailKind::modulo_context:
      return failure();
    }
    rewriter.setInsertionPoint(op);
    leaves(rewriter, op.getLoc());
    return success();
  }
};

} // namespace

FrozenRewritePatternSet accountPatterns(MLIRContext *ctx, const Layouts &layouts,
                                        const Runtime &runtime) {
  RewritePatternSet tells(ctx);
  tells.add<TellTake, TellUnique, TellRecycle, TellFree, TellReturn, TellTailCall>(ctx, layouts,
                                                                                    runtime);
  return FrozenRewritePatternSet(std::move(tells));
}

void keepAccount(FuncOp fn, const FrozenRewritePatternSet &tells, const Runtime &runtime) {
  uint64_t bound = fn.getFrameBound();
  // A call that holds nothing at any allocation keeps no account.
  if (bound == 0)
    return;
  walkAndApplyPatterns(fn, tells);
  Location loc = fn.getLoc();
  OpBuilder b = OpBuilder::atBlockBegin(&fn.getBody().front());
  runtime.call(b, loc, idr::runtime::helper::peakEnter,
               ValueRange{staticAddress(b, loc, StaticNames::text(fn.getSymName())),
                          i64Constant(b, loc, static_cast<int64_t>(bound))});
}

} // namespace idr::conversion
