// idr.lower:scalars: the patterns of crashes, forged worlds, loops that
// need not end, and the scalar operations whose meaning is more than
// arith's.

export module idr.lower:scalars;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :idrPattern;
import :runtime;
import :words;

using namespace mlir;

namespace idr::lower {

namespace {

// The runtime's crash, which does not return; the
// ub.unreachable after it stays.
struct LowerCrash : IdrPattern<CrashOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CrashOp op, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.crash(rewriter, op.getLoc(), op.getMessage());
    rewriter.eraseOp(op);
    return success();
  }
};

// A forged world has no runtime form, like every world.
struct LowerWorldNew : IdrPattern<WorldNewOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(WorldNewOp op, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
    return success();
  }
};

struct LowerMayLoop : IdrPattern<MayLoopOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(MayLoopOp op, OpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.mayLoop(rewriter, op.getLoc());
    rewriter.eraseOp(op);
    return success();
  }
};

template <typename OpT>
struct LowerDivision : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getLhs(), b = adaptor.getRhs();
    Type type = a.getType();
    unsigned width = type.getIntOrFloatBitWidth();
    auto constant = [&](const APInt &value) -> Value {
      return arith::ConstantOp::create(rewriter, loc, IntegerAttr::get(type, value));
    };
    Value result;
    // The divisor is not zero: a zero one ends the program at its guard.
    if (!op.getIsSigned()) {
      result = OpT::quotient ? Value(arith::DivUIOp::create(rewriter, loc, a, b))
                             : Value(arith::RemUIOp::create(rewriter, loc, a, b));
    } else {
      Value zero = constant(APInt::getZero(width));
      Value one = constant(APInt(width, 1));
      // MIN / -1 uses divisor 1, which gives MIN and 0: exactly the wrapped
      // Euclidean results.
      Value min = constant(APInt::getSignedMinValue(width));
      Value minusOne = constant(APInt::getAllOnes(width));
      Value isMin = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::eq, a, min);
      Value isM1 = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::eq, b, minusOne);
      Value overflow = arith::AndIOp::create(rewriter, loc, isMin, isM1);
      Value d = arith::SelectOp::create(rewriter, loc, overflow, one, b);
      Value q = arith::DivSIOp::create(rewriter, loc, a, d);
      Value r = arith::RemSIOp::create(rewriter, loc, a, d);
      Value negative = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::slt, r, zero);
      Value positive = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::sgt, d, zero);
      if constexpr (OpT::quotient) {
        Value down = arith::SubIOp::create(rewriter, loc, q, one);
        Value up = arith::AddIOp::create(rewriter, loc, q, one);
        Value adjusted = arith::SelectOp::create(rewriter, loc, positive, down, up);
        result = arith::SelectOp::create(rewriter, loc, negative, adjusted, q);
      } else {
        Value plus = arith::AddIOp::create(rewriter, loc, r, d);
        Value minus = arith::SubIOp::create(rewriter, loc, r, d);
        Value adjusted = arith::SelectOp::create(rewriter, loc, positive, plus, minus);
        result = arith::SelectOp::create(rewriter, loc, negative, adjusted, r);
      }
    }
    rewriter.replaceOp(op, result);
    return success();
  }
};

// A shift defined for every amount, as idrisShift folds it: the count of
// places is taken masked to the width, so no arith shift is ever poison,
// and the amounts from the width up select the fill instead.
template <typename OpT>
struct LowerShift : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getLhs(), amount = adaptor.getRhs();
    Type type = a.getType();
    unsigned width = type.getIntOrFloatBitWidth();
    auto constant = [&](uint64_t value) -> Value {
      return arith::ConstantOp::create(rewriter, loc, IntegerAttr::get(type, APInt(width, value)));
    };
    auto cmp = [&](arith::CmpIPredicate p, Value x, Value y) -> Value {
      return arith::CmpIOp::create(rewriter, loc, p, x, y);
    };
    Value zero = constant(0);
    bool isSigned = op.getIsSigned();
    // The places to move, and whether a signed amount turns the direction.
    Value turned = isSigned ? cmp(arith::CmpIPredicate::slt, amount, zero) : Value();
    Value places = !isSigned ? amount
                             : Value(arith::SelectOp::create(
                                   rewriter, loc, turned,
                                   arith::SubIOp::create(rewriter, loc, zero, amount), amount));
    Value huge = cmp(arith::CmpIPredicate::uge, places, constant(width));
    Value masked = arith::AndIOp::create(rewriter, loc, places, constant(width - 1));
    Value leftward = arith::SelectOp::create(
        rewriter, loc, huge, zero, arith::ShLIOp::create(rewriter, loc, a, masked));
    Value fill = isSigned ? Value(arith::ShRSIOp::create(rewriter, loc, a, constant(width - 1)))
                          : zero;
    Value rightward = arith::SelectOp::create(
        rewriter, loc, huge, fill,
        isSigned ? Value(arith::ShRSIOp::create(rewriter, loc, a, masked))
                 : Value(arith::ShRUIOp::create(rewriter, loc, a, masked)));
    Value result = OpT::left ? leftward : rightward;
    if (isSigned)
      result = arith::SelectOp::create(rewriter, loc, turned, OpT::left ? rightward : leftward,
                                       result);
    rewriter.replaceOp(op, result);
    return success();
  }
};

struct LowerToChar : IdrPattern<ToCharOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ToCharOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value x = adaptor.getValue();
    auto i64 = rewriter.getI64Type();
    if (x.getType().getIntOrFloatBitWidth() < 64)
      x = op.getIsSigned() ? Value(arith::ExtSIOp::create(rewriter, loc, i64, x))
                           : Value(arith::ExtUIOp::create(rewriter, loc, i64, x));
    auto c = [&](int64_t v) { return constantI64(rewriter, loc, v); };
    // Unsigned comparison treats negative signed values as huge: not scalar.
    auto ule = arith::CmpIPredicate::ule, uge = arith::CmpIPredicate::uge;
    Value low = arith::CmpIOp::create(rewriter, loc, ule, x, c(0xD7FF));
    Value hiA = arith::CmpIOp::create(rewriter, loc, uge, x, c(0xE000));
    Value hiB = arith::CmpIOp::create(rewriter, loc, ule, x, c(0x10FFFF));
    Value high = arith::AndIOp::create(rewriter, loc, hiA, hiB);
    Value scalar = arith::OrIOp::create(rewriter, loc, low, high);
    Value narrow = arith::TruncIOp::create(rewriter, loc, rewriter.getI32Type(), x);
    Value zero = arith::ConstantOp::create(rewriter, loc, rewriter.getI32IntegerAttr(0));
    rewriter.replaceOpWithNewOp<arith::SelectOp>(op, scalar, narrow, zero);
    return success();
  }
};

// to_byte: the low byte of a value from 0 to 255, which its guard checked.
struct LowerToByte : IdrPattern<ToByteOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(ToByteOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<arith::TruncIOp>(op, rewriter.getI8Type(), adaptor.getValue());
    return success();
  }
};

} // namespace

// The patterns of crashes, of what has no runtime form (a forged world),
// of the effect a loop that need not end keeps, and of the scalar
// operations whose meaning is more than arith's: division, shifts, chars and
// bytes.
export void populateScalarPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                   layout::Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerCrash, LowerWorldNew, LowerMayLoop, LowerToChar, LowerToByte,
               LowerDivision<DivOp>, LowerDivision<ModOp>, LowerShift<ShlOp>, LowerShift<ShrOp>>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::lower
