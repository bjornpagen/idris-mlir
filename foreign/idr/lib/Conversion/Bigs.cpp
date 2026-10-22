// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower, for bigs and naturals: the ops that are no call of
// one runtime function, a natural made an extent and a numeral made a
// natural or made of one. Every other big op is the plain call of its
// runtime function (RuntimeCalls.cpp), whose small case the runtime keeps
// inline, so the tagged arithmetic exists once and is inlined wherever the
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
#include "llvm/Support/MathExtras.h"

// The runtime's C ABI: the small Integer word's range.
#include "idris_rt.h"

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

// Whether every value of the integer type `number` is in the small range,
// so the natural of each is a small word and never a cell.
bool fitsSmall(Type number) {
  return llvm::maxUIntN(number.getIntOrFloatBitWidth()) <=
         static_cast<uint64_t>(IDRIS_RT_SMALL_MAX);
}

} // namespace

// A numeral's value as a natural. A numeral whose bound is open is held as
// its natural already. One held in a number of a fixed width is below the
// width's top, as Idris proved: where every number of the width is in the
// small range, its natural is the small word 2v + 1, as
// idris_rt_small_word makes it (an inline function emitted code cannot
// call); where a number of the width may lie past it, its natural is the
// runtime's of an unsigned word, big.from_uint's function, whose small case
// the runtime keeps inline. Essential: the three are the ways a numeral's
// bound can be held.
Value naturalOf(OpBuilder &b, Location loc, const Runtime &runtime, layout::Component held,
                Value numeral) {
  if (held.word == layout::Word::Big)
    return numeral;
  if (!fitsSmall(held.type))
    return runtime.call(b, loc, idr::runtime::Abi<BigFromUintOp>::entry, numeral).getResult();
  Value wide = arith::ExtUIOp::create(b, loc, b.getI64Type(), numeral);
  Value one = arith::ConstantIntOp::create(b, loc, 1, 64);
  Value twice = arith::ShLIOp::create(
      b, loc, wide, one, arith::IntegerOverflowFlags::nsw | arith::IntegerOverflowFlags::nuw);
  return arith::OrIOp::create(b, loc, twice, one);
}

// A natural as a numeral of the bound Idris proved it below, with no test.
// A numeral whose bound is open is held as the natural. Held in a number of
// a fixed width, the natural is below the width's top: where every number
// of the width is in the small range, the natural is a small word, whose
// value is the word shifted right as idris_rt_small_value reads it, which
// the width holds; where a number of the width may lie past it, the value
// is the runtime's word of a big, big.to_int's function.
Value numeralOf(OpBuilder &b, Location loc, const Runtime &runtime, layout::Component held,
                Value natural) {
  if (held.word == layout::Word::Big)
    return natural;
  if (!fitsSmall(held.type))
    return runtime.call(b, loc, idr::runtime::Abi<BigToIntOp>::entry, natural).getResult();
  Value one = arith::ConstantIntOp::create(b, loc, 1, 64);
  Value value = arith::ShRUIOp::create(b, loc, natural, one);
  return arith::TruncIOp::create(b, loc, held.type, value, arith::IntegerOverflowFlags::nuw);
}

namespace {

// numeral.to_nat at the way its operand's bound is held.
struct LowerNumeralToNat : IdrPattern<NumeralToNatOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(NumeralToNatOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    layout::Component held = layouts.components(op.getValue().getType()).front();
    rewriter.replaceOp(op, naturalOf(rewriter, op.getLoc(), runtime, held, adaptor.getValue()));
    return success();
  }
};

// numeral.of_nat at the way its result's bound is held.
struct LowerNumeralOfNat : IdrPattern<NumeralOfNatOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(NumeralOfNatOp op, OpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    layout::Component held = layouts.components(op.getResult().getType()).front();
    rewriter.replaceOp(op, numeralOf(rewriter, op.getLoc(), runtime, held, adaptor.getValue()));
    return success();
  }
};

} // namespace

// The patterns of the big ops that are no call of one runtime function: a
// natural made an extent, and a numeral made a natural or made of one.
void populateBigPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                         const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerNatToExtent, LowerNumeralToNat, LowerNumeralOfNat>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
