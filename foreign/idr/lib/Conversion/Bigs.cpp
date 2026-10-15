// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower, for bigs and naturals: the ops that have no runtime
// function. Every other big op is the plain call of its runtime function
// (RuntimeCalls.cpp), whose small case the runtime keeps inline, so the
// tagged arithmetic exists once and is inlined wherever the runtime's
// bitcode is joined to the program.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {
namespace {

// The low bit, which is 1 exactly in a small word.
Value lowBit(OpBuilder &b, Location loc, Value word) {
  return arith::TruncIOp::create(b, loc, b.getI1Type(), word);
}

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

} // namespace

// The patterns of the big ops that have no runtime function: a natural made
// a big, which is the same word; a small big made of a word that fits; and
// a natural made an extent.
void populateBigPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                         const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerAsItself<NatToBigOp>, LowerBigSmall, LowerNatToExtent>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
