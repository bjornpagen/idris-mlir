// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The guards: each decides its own condition once, over where its operands'
// values come from (its `decide`, a template over fold::Where, in
// Ops/Guards.h): its folder and the folders of the ops it guards ask it of
// the constants ops hold, and the e-graph of its own values. Each reading's
// condition is defined here once, and each guard narrows its operand's
// range by its condition. Every condition but one is inline arithmetic, a
// meaning of Numeric/Inline.h over words and over intervals, as the
// lowering's test is the same meaning over arith (Conversion/Checks.cpp):
// one condition, written once, over what the guard tests (a string's
// length, a Double's bits). What a handle holds is the run's own state,
// which only the run knows.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Numeric/Inline.h"
#include "idr/IR/Numeric/Intervals.h"
#include "idr/IR/Numeric/Word.h"

#include <algorithm>
#include <bit>
#include <limits>
#include <optional>

using namespace mlir;
using namespace idr;

namespace {

// A word of `value`'s width, its bits.
numeric::Word wordOf(const APInt &value) {
  return numeric::Words::of(value.getZExtValue(), value.getBitWidth());
}

// The 64-bit word of an i64 the runtime gives, a string's length.
numeric::Word word64(int64_t value) {
  return numeric::Words::of(static_cast<uint64_t>(value), 64);
}

// What a truth of words knows: words are exact, so it holds or it fails.
numeric::Known knownOf(numeric::Bit truth) {
  return truth.holds ? numeric::Known::Holds : numeric::Known::Fails;
}

// Whether an interval states an integer: one of no width is upstream's mark
// of a value it does not see as one.
bool statesInteger(const ConstantIntRanges &range) { return range.umin().getBitWidth() != 0; }

} // namespace

//===----------------------------------------------------------------------===//
// The conditions, each over what a guard reads
//===----------------------------------------------------------------------===//

// A constant is the one interval it is, at its own width, which decides a
// word's and a big's in the small range alike.
numeric::Known guards::nonzero(const APInt &value) {
  return numeric::nonzero(numeric::Intervals{}, ConstantIntRanges::constant(value)).known;
}

// The runtime's comparison is a big's one meaning of order.
numeric::Known guards::nonzero(idris_rt_big value) {
  idris_rt_big zero = runtime::Abi<BigSmallOp>::function(0);
  return runtime::Abi<BigCmpOp>::function(value, zero) == 0 ? numeric::Known::Fails
                                                             : numeric::Known::Holds;
}

// Zero is outside the divisor's interval, or is all of it; an Integer's
// interval is its value's (idr::ranges), so the same test decides it.
numeric::Known guards::nonzero(const ConstantIntRanges &range) {
  if (!statesInteger(range))
    return numeric::Known::Unknown;
  return numeric::nonzero(numeric::Intervals{}, range).known;
}

int64_t guards::lengthOf(const idris_rt_str *str) {
  return runtime::Abi<StrLengthOp>::function(str);
}

numeric::Known guards::inBounds(const APInt &index, int64_t length) {
  return knownOf(numeric::inBounds(numeric::Words{}, wordOf(index), word64(length)));
}

numeric::Known guards::inBounds(const ConstantIntRanges &index, int64_t length) {
  if (!statesInteger(index))
    return numeric::Known::Unknown;
  numeric::Intervals d;
  return numeric::inBounds(d, index, d.constant(length, index)).known;
}

numeric::Known guards::nonempty(int64_t length) {
  return knownOf(numeric::nonempty(numeric::Words{}, word64(length)));
}

numeric::Known guards::finite(double value) {
  return knownOf(numeric::finite(numeric::Words{},
                                 numeric::Words::of(std::bit_cast<uint64_t>(value), 64)));
}

numeric::Known guards::inRange(const APInt &offset, const APInt &count, const APInt &size) {
  return knownOf(numeric::inRange(numeric::Words{}, wordOf(offset), wordOf(count), wordOf(size)));
}

numeric::Known guards::inRange(const ConstantIntRanges &offset, const ConstantIntRanges &count,
                               const ConstantIntRanges &size) {
  if (!statesInteger(offset) || !statesInteger(count) || !statesInteger(size))
    return numeric::Known::Unknown;
  return numeric::inRange(numeric::Intervals{}, offset, count, size).known;
}

numeric::Known guards::fitsByte(const APInt &value) {
  return knownOf(numeric::fitsByte(numeric::Words{}, wordOf(value)));
}

numeric::Known guards::fitsByte(const ConstantIntRanges &range) {
  if (!statesInteger(range))
    return numeric::Known::Unknown;
  return numeric::fitsByte(numeric::Intervals{}, range).known;
}

//===----------------------------------------------------------------------===//
// Folding
//===----------------------------------------------------------------------===//

namespace {

// Whether a guard's condition holds of the constants ops hold of its
// operands: its decision at the attribute place, each constant an integer's
// one interval where it is one.
template <class G>
bool holdsOf(G guard, ArrayRef<Attribute> constants) {
  fold::InAttributes where(guard.getContext());
  return G::decide(where, fold::rangesOf(constants), constants) == numeric::Known::Holds;
}

} // namespace

// The value a guard checks, where its condition holds of its constants.
// Nothing otherwise: a guard that would crash keeps its crash, which the
// e-graph makes a plain crash where its condition is refuted.
OpFoldResult CheckNonzeroOp::fold(FoldAdaptor adaptor) {
  return holdsOf(*this, adaptor.getOperands()) ? OpFoldResult(getValue()) : OpFoldResult();
}
OpFoldResult CheckInBoundsOp::fold(FoldAdaptor adaptor) {
  return holdsOf(*this, adaptor.getOperands()) ? OpFoldResult(getIndex()) : OpFoldResult();
}
OpFoldResult CheckNonemptyOp::fold(FoldAdaptor adaptor) {
  return holdsOf(*this, adaptor.getOperands()) ? OpFoldResult(getStr()) : OpFoldResult();
}
OpFoldResult CheckFiniteOp::fold(FoldAdaptor adaptor) {
  return holdsOf(*this, adaptor.getOperands()) ? OpFoldResult(getValue()) : OpFoldResult();
}
OpFoldResult CheckRangeOp::fold(FoldAdaptor adaptor) {
  return holdsOf(*this, adaptor.getOperands()) ? OpFoldResult(getOffset()) : OpFoldResult();
}
OpFoldResult CheckByteOp::fold(FoldAdaptor adaptor) {
  return holdsOf(*this, adaptor.getOperands()) ? OpFoldResult(getValue()) : OpFoldResult();
}
// Never folds: its condition never holds of a constant (its decide).
OpFoldResult CheckHoldsStringOp::fold(FoldAdaptor) { return {}; }

//===----------------------------------------------------------------------===//
// Ranges
//===----------------------------------------------------------------------===//

namespace {

// `range`, an i64's, narrowed to the signed interval [lo, hi] the guard's
// condition leaves. Where it leaves nothing the guard always crashes and
// nothing reads its result, so the range stays as it was.
ConstantIntRanges within(const ConstantIntRanges &range, int64_t lo, int64_t hi) {
  if (range.smin().getBitWidth() != 64 || lo > hi)
    return range;
  ConstantIntRanges narrowed = range.intersection(ConstantIntRanges::fromSigned(
      APInt(64, static_cast<uint64_t>(lo), /*isSigned=*/true),
      APInt(64, static_cast<uint64_t>(hi), /*isSigned=*/true)));
  if (narrowed.smin().sgt(narrowed.smax()) || narrowed.umin().ugt(narrowed.umax()))
    return range;
  return narrowed;
}

} // namespace

// Not zero: an end of the range at zero moves past it. An Integer's range
// is its value's, so the same holds of it.
void CheckNonzeroOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                       SetIntRangeFn setResultRange) {
  const ConstantIntRanges &range = ranges[0];
  unsigned width = range.umin().getBitWidth();
  // No integer the analysis sees, or zero alone, which always crashes.
  if (width < 2 || range.umax().isZero() || (range.smin().isZero() && range.smax().isZero())) {
    setResultRange(getChecked(), range);
    return;
  }
  APInt one(width, 1);
  setResultRange(getChecked(),
                 ConstantIntRanges(range.umin().isZero() ? one : range.umin(), range.umax(),
                                   range.smin().isZero() ? one : range.smin(),
                                   range.smax().isZero() ? APInt::getAllOnes(width)
                                                         : range.smax()));
}

// At least 0, and below the length of what it indexes, which no range
// states: a length is at most the largest i64. An index's range is at 64
// bits too, the width upstream stores an index's interval at.
void CheckInBoundsOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                                    SetIntLatticeFn setResultRange) {
  if (ranges[0].isUninitialized())
    return;
  setResultRange(getChecked(), IntegerValueRange(within(ranges[0].getValue(), 0,
                                                        std::numeric_limits<int64_t>::max() - 1)));
}

// At least 0, and at most the size's greatest value less the least count,
// which is not negative either.
void CheckRangeOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                     SetIntRangeFn setResultRange) {
  const APInt &count = ranges[1].smin(), &size = ranges[2].smax();
  if (count.getBitWidth() != 64 || size.getBitWidth() != 64 || size.isNegative()) {
    setResultRange(getChecked(), ranges[0]);
    return;
  }
  int64_t least = std::max<int64_t>(count.getSExtValue(), 0);
  setResultRange(getChecked(), within(ranges[0], 0, size.getSExtValue() - least));
}
