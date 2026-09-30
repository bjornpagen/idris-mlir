// Phase 2 of idr-lower, for bigs and naturals: each op computes its small
// case inline and calls the runtime only when an operand is a GMP integer or
// the result leaves the small range.
//
// A small big is the word 2v+1, so the tagged words themselves are almost
// the arithmetic: a+b-1 is the sum, a-b+1 the difference, and (a>>1)*(b-1)+1
// the product. The LLVM overflow intrinsics on those words overflow exactly
// when the result leaves the small range. The runtime's functions stay the
// one meaning of each op: this is their small case restated, and the cold
// path is the whole function.

#include "Lower/Patterns.h"

#include "mlir/Dialect/SCF/IR/SCF.h"

using namespace mlir;

namespace idr::lower {
namespace {

Value constantI64(OpBuilder &b, Location loc, int64_t value) {
  return arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(value));
}

// The low bit, which is 1 exactly in a small word.
Value lowBit(OpBuilder &b, Location loc, Value word) {
  return arith::TruncIOp::create(b, loc, b.getI1Type(), word);
}

// The wrapped result of an overflow intrinsic and whether it overflowed.
template <typename OpT>
std::pair<Value, Value> withOverflow(OpBuilder &b, Location loc, Value x, Value y) {
  auto type = LLVM::LLVMStructType::getLiteral(b.getContext(), {x.getType(), b.getI1Type()});
  Value pair = OpT::create(b, loc, type, x, y);
  return {LLVM::ExtractValueOp::create(b, loc, pair, 0),
          LLVM::ExtractValueOp::create(b, loc, pair, 1)};
}

// `fast` where `ok` holds, else what `cold` computes. The test is expected
// to hold (llvm.expect, which LLVM makes branch weights), so the runtime
// call is laid out off the hot path.
Value unlessCold(OpBuilder &b, Location loc, Value ok, Value fast,
                 function_ref<Value(OpBuilder &, Location)> cold) {
  Value yes = arith::ConstantOp::create(b, loc, b.getBoolAttr(true));
  Value likely = LLVM::ExpectOp::create(b, loc, ok, yes);
  auto branch = scf::IfOp::create(
      b, loc, likely,
      [&](OpBuilder &then, Location at) { scf::YieldOp::create(then, at, fast); },
      [&](OpBuilder &otherwise, Location at) {
        scf::YieldOp::create(otherwise, at, cold(otherwise, at));
      });
  return branch.getResult(0);
}

template <typename OpT>
Value callRuntime(OpBuilder &b, Location loc, Runtime &runtime, Type result, ValueRange args) {
  return runtime.call(b, loc, OpT::getHelper(), result, args);
}

// The sum, difference and product: both operands small, and no overflow.
template <typename OpT>
struct LowerBigArith : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getLhs(), b = adaptor.getRhs();
    Value one = constantI64(rewriter, loc, 1);
    Value bTwice = arith::SubIOp::create(rewriter, loc, b, one);
    Value result, overflow;
    if constexpr (std::is_same_v<OpT, BigAddOp>) {
      std::tie(result, overflow) =
          withOverflow<LLVM::SAddWithOverflowOp>(rewriter, loc, a, bTwice);
    } else if constexpr (std::is_same_v<OpT, BigSubOp>) {
      std::tie(result, overflow) =
          withOverflow<LLVM::SSubWithOverflowOp>(rewriter, loc, a, bTwice);
    } else {
      static_assert(std::is_same_v<OpT, BigMulOp>);
      Value aValue = arith::ShRSIOp::create(rewriter, loc, a, one);
      Value product;
      std::tie(product, overflow) =
          withOverflow<LLVM::SMulWithOverflowOp>(rewriter, loc, aValue, bTwice);
      // An even product below 2^63 plus one cannot overflow.
      result = arith::OrIOp::create(rewriter, loc, product, one);
    }
    Value small = lowBit(rewriter, loc, arith::AndIOp::create(rewriter, loc, a, b));
    Value fits = arith::XOrIOp::create(rewriter, loc, overflow,
                                       arith::ConstantOp::create(rewriter, loc,
                                                                 rewriter.getBoolAttr(true)));
    Value ok = arith::AndIOp::create(rewriter, loc, small, fits);
    rewriter.replaceOp(op, unlessCold(rewriter, loc, ok, result, [&](OpBuilder &cold, Location at) {
                         return callRuntime<OpT>(cold, at, this->runtime, a.getType(),
                                                 ValueRange{a, b});
                       }));
    return success();
  }
};

// The predecessor of a natural that is not zero: a small one is at least the
// word 3, so the word minus 2 is its predecessor and cannot overflow.
struct LowerBigPred : IdrPattern<BigPredOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(BigPredOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getValue();
    Value result = arith::SubIOp::create(rewriter, loc, a, constantI64(rewriter, loc, 2),
                                         arith::IntegerOverflowFlags::nsw);
    rewriter.replaceOp(op, unlessCold(rewriter, loc, lowBit(rewriter, loc, a), result,
                                      [&](OpBuilder &cold, Location at) {
                                        return callRuntime<BigPredOp>(cold, at, runtime,
                                                                      a.getType(), a);
                                      }));
    return success();
  }
};

// An Integer as a natural: a small negative one is the small 0 (the word
// 1); a small word is negative exactly when its value is.
struct LowerNatFromBig : IdrPattern<NatFromBigOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(NatFromBigOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getValue();
    Value negative = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::slt, a,
                                           constantI64(rewriter, loc, 0));
    Value result = arith::SelectOp::create(rewriter, loc, negative, constantI64(rewriter, loc, 1), a);
    rewriter.replaceOp(op, unlessCold(rewriter, loc, lowBit(rewriter, loc, a), result,
                                      [&](OpBuilder &cold, Location at) {
                                        return callRuntime<NatFromBigOp>(cold, at, runtime,
                                                                         a.getType(), a);
                                      }));
    return success();
  }
};

arith::CmpIPredicate signedPredicate(CmpPredicate predicate) {
  switch (predicate) {
  case CmpPredicate::eq:
    return arith::CmpIPredicate::eq;
  case CmpPredicate::lt:
    return arith::CmpIPredicate::slt;
  case CmpPredicate::lte:
    return arith::CmpIPredicate::sle;
  case CmpPredicate::gt:
    return arith::CmpIPredicate::sgt;
  case CmpPredicate::gte:
    return arith::CmpIPredicate::sge;
  }
  llvm_unreachable("a comparison predicate");
}

// Two small words order as their values do. Each integer has one
// representation, so equality needs only one small operand: a small word
// equals nothing but itself. The runtime's three-way comparison decides the
// rest.
struct LowerBigCmp : IdrPattern<BigCmpOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(BigCmpOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getLhs(), b = adaptor.getRhs();
    arith::CmpIPredicate predicate = signedPredicate(op.getPredicate());
    Value result = arith::CmpIOp::create(rewriter, loc, predicate, a, b);
    Value ok = op.getPredicate() == CmpPredicate::eq
                   ? lowBit(rewriter, loc, arith::OrIOp::create(rewriter, loc, a, b))
                   : lowBit(rewriter, loc, arith::AndIOp::create(rewriter, loc, a, b));
    rewriter.replaceOp(op, unlessCold(rewriter, loc, ok, result, [&](OpBuilder &cold, Location at) {
                         Value order = callRuntime<BigCmpOp>(cold, at, runtime, cold.getI32Type(),
                                                             ValueRange{a, b});
                         Value zero = arith::ConstantOp::create(cold, at, cold.getI32IntegerAttr(0));
                         return arith::CmpIOp::create(cold, at, predicate, order, zero).getResult();
                       }));
    return success();
  }
};

// An integer as a big: one narrower than the small range is always small,
// its value doubled plus one; a 64-bit one is small when doubling it does
// not overflow (signed) or when it is below 2^62 (unsigned).
struct LowerBigFromInt : IdrPattern<BigFromIntOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(BigFromIntOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value x = adaptor.getValue();
    bool isSigned = op.getIsSigned();
    auto i64 = rewriter.getI64Type();
    unsigned width = x.getType().getIntOrFloatBitWidth();
    Value one = constantI64(rewriter, loc, 1);
    if (width < 64) {
      Value wide = isSigned ? Value(arith::ExtSIOp::create(rewriter, loc, i64, x))
                            : Value(arith::ExtUIOp::create(rewriter, loc, i64, x));
      Value twice = arith::ShLIOp::create(rewriter, loc, wide, one, arith::IntegerOverflowFlags::nsw);
      rewriter.replaceOp(op, arith::OrIOp::create(rewriter, loc, twice, one));
      return success();
    }
    Value twice, ok;
    if (isSigned) {
      Value overflow;
      std::tie(twice, overflow) = withOverflow<LLVM::SAddWithOverflowOp>(rewriter, loc, x, x);
      ok = arith::XOrIOp::create(rewriter, loc, overflow,
                                 arith::ConstantOp::create(rewriter, loc, rewriter.getBoolAttr(true)));
    } else {
      twice = arith::ShLIOp::create(rewriter, loc, x, one);
      ok = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ult, x,
                                 constantI64(rewriter, loc, int64_t{1} << 62));
    }
    Value result = arith::OrIOp::create(rewriter, loc, twice, one);
    std::string name = (BigFromIntOp::getHelper() + (isSigned ? "_s" : "_u")).str();
    rewriter.replaceOp(op, unlessCold(rewriter, loc, ok, result, [&](OpBuilder &cold, Location at) {
                         return runtime.call(cold, at, name, i64, x);
                       }));
    return success();
  }
};

// The small big of a word that fits: its value doubled plus one.
struct LowerBigSmall : IdrPattern<BigSmallOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(BigSmallOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value one = constantI64(rewriter, loc, 1);
    Value twice = arith::ShLIOp::create(rewriter, loc, adaptor.getValue(), one,
                                        arith::IntegerOverflowFlags::nsw);
    rewriter.replaceOp(op, arith::OrIOp::create(rewriter, loc, twice, one));
    return success();
  }
};

// A big as an integer, wrapped to its width: a small one is its value, the
// word shifted right; the runtime gives a GMP integer's low 64 bits.
struct LowerBigToInt : IdrPattern<BigToIntOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(BigToIntOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getValue();
    Value value = arith::ShRSIOp::create(rewriter, loc, a, constantI64(rewriter, loc, 1));
    Value word = unlessCold(rewriter, loc, lowBit(rewriter, loc, a), value,
                            [&](OpBuilder &cold, Location at) {
                              return callRuntime<BigToIntOp>(cold, at, runtime,
                                                             cold.getI64Type(), a);
                            });
    Type type = op.getType();
    if (type != word.getType())
      word = arith::TruncIOp::create(rewriter, loc, type, word);
    rewriter.replaceOp(op, word);
    return success();
  }
};

} // namespace

void populateBigPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                         Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerBigArith<BigAddOp>, LowerBigArith<BigSubOp>, LowerBigArith<BigMulOp>,
               LowerBigPred, LowerNatFromBig, LowerBigCmp, LowerBigFromInt, LowerBigSmall, LowerBigToInt>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::lower
