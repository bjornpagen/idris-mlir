// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower, for bigs and naturals: the op that is no call of
// one runtime function. Every other big op is the plain call of its runtime
// function (RuntimeCalls.cpp), whose small case the runtime keeps inline,
// so the tagged arithmetic exists once and is inlined wherever the
// runtime's bitcode is joined to the program; a natural made a big is the
// same word (NoRuntimeForm).

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

// A natural as the extent of an array to be made: a small natural's value,
// the word shifted right as the runtime's idris_rt_small_value reads it
// (an inline function emitted code cannot call), which is below 2^62 and so
// fits an index; any other natural is past every allocation, which ends the
// run as out of memory, as the allocation would: no site, since running out
// of memory names no allocation.
struct LowerNatToExtent : IdrPattern<NatToExtentOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(NatToExtentOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value word = adaptor.getNatural();
    Value yes = arith::ConstantOp::create(rewriter, loc, rewriter.getBoolAttr(true));
    Value large = arith::XOrIOp::create(rewriter, loc, lowBit(rewriter, loc, word), yes);
    runtime.outOfMemoryIf(rewriter, loc, large);
    Value one = arith::ConstantIntOp::create(rewriter, loc, 1, 64);
    Value value = arith::ShRUIOp::create(rewriter, loc, word, one);
    rewriter.replaceOpWithNewOp<arith::IndexCastOp>(op, rewriter.getIndexType(), value);
    return success();
  }
};

} // namespace

// The pattern of the big op that is no call of one runtime function: a
// natural made an extent.
void populateBigPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                         const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerNatToExtent>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
