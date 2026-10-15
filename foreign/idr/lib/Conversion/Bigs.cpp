// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower, for bigs and naturals: each op computes its small
// case inline and calls the runtime only when an operand is a GMP integer or
// the result leaves the small range.
//
// A small big is the word 2v+1, so the tagged words themselves are almost the
// arithmetic: a+b-1 is the sum, a-b+1 the difference, and (a>>1)*(b-1)+1 the
// product. The LLVM overflow intrinsics on those words overflow exactly when
// the result leaves the small range. The runtime's functions stay the one
// meaning of each op: this is their small case restated, and the cold path is
// the whole function.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Transforms/DialectConversion.h"

// The word op of each big op that names one: BigToWord.
#include "idr/IR/IdrBigToWord.inc"

#include <type_traits>

using namespace mlir;

namespace idr::conversion {
namespace {

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

// The cold path: the runtime function of `op` on its words `args`, one per
// operand.
template <typename OpT>
Value callRuntime(OpBuilder &b, Runtime &runtime, OpT op, ValueRange args) {
  SmallVector<ValueRange> operands;
  for (unsigned i = 0; i < args.size(); ++i)
    operands.push_back(args.slice(i, 1));
  return runtime.call(b, op, runtimeFunctionOf(op), operands);
}

// The word op `OpT` names, and its constant second operand, if any.
template <typename OpT>
using WordOf = typename BigToWord<OpT>::Op;
template <typename OpT>
constexpr bool hasWordConstant = requires { BigToWord<OpT>::constant; };

// The sum, difference and product: both operands small, and no overflow.
template <typename OpT>
struct LowerBigArith : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    using Word = WordOf<OpT>;
    Location loc = op.getLoc();
    Value a = adaptor.getLhs(), b = adaptor.getRhs();
    Value one = arith::ConstantIntOp::create(rewriter, loc, 1, 64);
    Value bTwice = arith::SubIOp::create(rewriter, loc, b, one);
    Value result, overflow;
    if constexpr (std::is_same_v<Word, arith::AddIOp>) {
      std::tie(result, overflow) =
          withOverflow<LLVM::SAddWithOverflowOp>(rewriter, loc, a, bTwice);
    } else if constexpr (std::is_same_v<Word, arith::SubIOp>) {
      std::tie(result, overflow) =
          withOverflow<LLVM::SSubWithOverflowOp>(rewriter, loc, a, bTwice);
    } else {
      static_assert(std::is_same_v<Word, arith::MulIOp>,
                    "a big op's word op has a small case here");
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
    rewriter.replaceOp(op, unlessCold(rewriter, loc, ok, result, [&](OpBuilder &cold, Location) {
                         return callRuntime(cold, this->runtime, op, ValueRange{a, b});
                       }));
    return success();
  }
};

// The word op applied to a constant, in place: the word less twice the
// constant is the small big of the value less the constant. A predecessor's
// operand is a natural that is not zero, at least the constant, so the
// difference cannot overflow.
template <typename OpT>
struct LowerSmallStep : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    static_assert(std::is_same_v<WordOf<OpT>, arith::SubIOp>,
                  "a big op's word op on a constant has a small case here");
    Location loc = op.getLoc();
    Value a = adaptor.getValue();
    Value step = arith::ConstantIntOp::create(rewriter, loc, 2 * BigToWord<OpT>::constant, 64);
    Value result = arith::SubIOp::create(rewriter, loc, a, step, arith::IntegerOverflowFlags::nsw);
    rewriter.replaceOp(op, unlessCold(rewriter, loc, lowBit(rewriter, loc, a), result,
                                      [&](OpBuilder &cold, Location) {
                                        return callRuntime(cold, this->runtime, op, a);
                                      }));
    return success();
  }
};

// The larger of the value and a constant: a small word's order is its
// value's, so it is the larger of the word and the constant's small word.
// A natural from an Integer is the word, or the small 0 (the word 1) when a
// small word is negative.
template <typename OpT>
struct LowerSmallMax : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getValue();
    Value least =
        arith::ConstantIntOp::create(rewriter, loc, 2 * BigToWord<OpT>::constant + 1, 64);
    Value result = arith::MaxSIOp::create(rewriter, loc, a, least);
    rewriter.replaceOp(op, unlessCold(rewriter, loc, lowBit(rewriter, loc, a), result,
                                      [&](OpBuilder &cold, Location) {
                                        return callRuntime(cold, this->runtime, op, a);
                                      }));
    return success();
  }
};

// Two small words order as their values do. Each integer has one
// representation, so equality needs only one small operand: a small word
// equals nothing but itself. The runtime's three-way comparison decides the
// rest.
template <typename OpT>
struct LowerBigCmp : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getLhs(), b = adaptor.getRhs();
    arith::CmpIPredicate predicate = layout::signedPredicate(op.getPredicate());
    Value result = arith::CmpIOp::create(rewriter, loc, predicate, a, b);
    Value ok = op.getPredicate() == CmpPredicate::eq
                   ? lowBit(rewriter, loc, arith::OrIOp::create(rewriter, loc, a, b))
                   : lowBit(rewriter, loc, arith::AndIOp::create(rewriter, loc, a, b));
    rewriter.replaceOp(op, unlessCold(rewriter, loc, ok, result, [&](OpBuilder &cold, Location at) {
                         Value order = callRuntime(cold, this->runtime, op, ValueRange{a, b});
                         Value zero = arith::ConstantIntOp::create(cold, at, 0, 32);
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
    Value one = arith::ConstantIntOp::create(rewriter, loc, 1, 64);
    if (width < 64) {
      Value wide = isSigned ? Value(arith::ExtSIOp::create(rewriter, loc, i64, x))
                            : Value(arith::ExtUIOp::create(rewriter, loc, i64, x));
      Value twice =
          arith::ShLIOp::create(rewriter, loc, wide, one, arith::IntegerOverflowFlags::nsw);
      rewriter.replaceOp(op, arith::OrIOp::create(rewriter, loc, twice, one));
      return success();
    }
    Value twice, ok;
    if (isSigned) {
      Value overflow;
      std::tie(twice, overflow) = withOverflow<LLVM::SAddWithOverflowOp>(rewriter, loc, x, x);
      Value yes = arith::ConstantOp::create(rewriter, loc, rewriter.getBoolAttr(true));
      ok = arith::XOrIOp::create(rewriter, loc, overflow, yes);
    } else {
      twice = arith::ShLIOp::create(rewriter, loc, x, one);
      ok = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ult, x,
                                 arith::ConstantIntOp::create(rewriter, loc, int64_t{1} << 62, 64));
    }
    Value result = arith::OrIOp::create(rewriter, loc, twice, one);
    rewriter.replaceOp(op, unlessCold(rewriter, loc, ok, result, [&](OpBuilder &cold, Location) {
                         return callRuntime(cold, runtime, op, x);
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
    Value one = arith::ConstantIntOp::create(rewriter, loc, 1, 64);
    Value twice = arith::ShLIOp::create(rewriter, loc, adaptor.getValue(), one,
                                        arith::IntegerOverflowFlags::nsw);
    rewriter.replaceOp(op, arith::OrIOp::create(rewriter, loc, twice, one));
    return success();
  }
};

// A big as an integer, wrapped to its width: a small one is its value, the
// word shifted right; the runtime gives a GMP integer's low 64 bits.
template <typename OpT>
struct LowerBigToInt : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename OpT::Adaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value a = adaptor.getValue();
    Value one = arith::ConstantIntOp::create(rewriter, loc, 1, 64);
    Value value = arith::ShRSIOp::create(rewriter, loc, a, one);
    Value word = unlessCold(rewriter, loc, lowBit(rewriter, loc, a), value,
                            [&](OpBuilder &cold, Location) {
                              return callRuntime(cold, this->runtime, op, a);
                            });
    Type type = op.getType();
    if (type != word.getType())
      word = arith::TruncIOp::create(rewriter, loc, type, word);
    rewriter.replaceOp(op, word);
    return success();
  }
};

// A natural as the extent of an array to be made: a small natural's value,
// the word shifted right, which is below 2^62 and so fits an index; any
// other natural is past every allocation, and crashes as the allocation
// would.
struct LowerNatToExtent : IdrPattern<NatToExtentOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(NatToExtentOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value word = adaptor.getNatural();
    Value yes = arith::ConstantOp::create(rewriter, loc, rewriter.getBoolAttr(true));
    Value large = arith::XOrIOp::create(rewriter, loc, lowBit(rewriter, loc, word), yes);
    runtime.crashIf(rewriter, loc, large, *op.getCrashCause());
    Value one = arith::ConstantIntOp::create(rewriter, loc, 1, 64);
    Value value = arith::ShRUIOp::create(rewriter, loc, word, one);
    rewriter.replaceOpWithNewOp<arith::IndexCastOp>(op, rewriter.getIndexType(), value);
    return success();
  }
};

// The small case of the big op `OpT`, by the word op it names.
template <typename OpT>
void addSmallCase(RewritePatternSet &patterns, const TypeConverter &converter,
                  const Layouts &layouts, Runtime &runtime) {
  using Word = WordOf<OpT>;
  MLIRContext *ctx = patterns.getContext();
  if constexpr (std::is_void_v<Word>)
    patterns.add<LowerAsItself<OpT>>(converter, ctx, layouts, runtime);
  else if constexpr (std::is_same_v<Word, arith::CmpIOp>)
    patterns.add<LowerBigCmp<OpT>>(converter, ctx, layouts, runtime, ownLowering);
  else if constexpr (std::is_same_v<Word, arith::MaxSIOp>)
    patterns.add<LowerSmallMax<OpT>>(converter, ctx, layouts, runtime, ownLowering);
  else if constexpr (std::is_same_v<Word, arith::TruncIOp>)
    patterns.add<LowerBigToInt<OpT>>(converter, ctx, layouts, runtime, ownLowering);
  else if constexpr (hasWordConstant<OpT>)
    patterns.add<LowerSmallStep<OpT>>(converter, ctx, layouts, runtime, ownLowering);
  else
    patterns.add<LowerBigArith<OpT>>(converter, ctx, layouts, runtime, ownLowering);
}

template <typename... Ops>
void addSmallCases(RewritePatternSet &patterns, const TypeConverter &converter,
                   const Layouts &layouts, Runtime &runtime) {
  (addSmallCase<Ops>(patterns, converter, layouts, runtime), ...);
}

} // namespace

// The patterns of bigs and naturals, whose small case is inline: each op
// that names a word op, and the integers made bigs, ahead of the call of
// the op's runtime function; and the ops that are a word alone.
void populateBigPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                         const Layouts &layouts, Runtime &runtime) {
  MLIRContext *ctx = patterns.getContext();
  addSmallCases<
#define GET_BIG_TO_WORD_LIST
#include "idr/IR/IdrBigToWord.inc"
      >(patterns, converter, layouts, runtime);
  patterns.add<LowerBigFromInt>(converter, ctx, layouts, runtime, ownLowering);
  patterns.add<LowerBigSmall, LowerNatToExtent>(converter, ctx, layouts, runtime);
}

} // namespace idr::conversion
