// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The guards: each decides its own condition on constants (its `holds`,
// which its folder and the folders of the ops it guards ask, through
// GuardedOp) and on intervals with the constants ops hold (its `decide`,
// which the e-graph's skeleton rule asks: a guard that holds goes, one that
// fails is a crash of its cause at its site), and narrows its operand's
// range by the condition. A condition on a constant no interval states is
// written once and read by both. Every condition but one is inline
// arithmetic, a meaning of Numeric/Inline.h over words and over intervals,
// as the lowering's test is the same meaning over arith
// (Conversion/Checks.cpp): one condition, written once, over what the guard
// tests (a string's length, a Double's bits). What a handle holds is the
// run's own state, which only the run knows.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Numeric/Inline.h"
#include "idr/IR/Numeric/Intervals.h"
#include "idr/IR/Numeric/Trait.h"
#include "idr/IR/Numeric/Word.h"

#include <algorithm>
#include <limits>
#include <optional>

using namespace mlir;
using namespace idr;

namespace {

// The 64-bit word of an i64 the runtime gives, a string's length.
numeric::Word word64(int64_t value) {
  return numeric::Words::of(static_cast<uint64_t>(value), 64);
}

// What a truth of words knows: words are exact, so it holds or it fails.
numeric::Known knownOf(numeric::Bit truth) {
  return truth.holds ? numeric::Known::Holds : numeric::Known::Fails;
}

// A divisor's constant, a word's or an Integer's (keyInteger), decided as
// the one interval it is, at its own width: an Integer's zero is the
// runtime's small 0, no word of the op's, and its interval states only a
// value within i64, so its constant decides it past i64 too.
numeric::Known constantNonzero(const APInt &value) {
  return numeric::nonzero(numeric::Intervals{}, ConstantIntRanges::constant(value)).known;
}

// The length of what is indexed, where an op holds it as a constant string:
// the runtime's count of its characters, its str.length's function. None
// for an array, or a string no constant holds.
std::optional<int64_t> lengthOf(Attribute indexed) {
  auto text = dyn_cast_or_null<StringAttr>(indexed);
  if (!text)
    return std::nullopt;
  fold::Scope scope(text.getContext());
  std::optional<const idris_rt_str *> runtime = fold::strOf(scope, text);
  if (!runtime)
    return std::nullopt;
  return runtime::Abi<StrLengthOp>::function(*runtime);
}

// A string of at least one character, where an op holds it: the
// condition over its length.
numeric::Known nonemptyOf(Attribute str) {
  std::optional<int64_t> length = lengthOf(str);
  return length ? knownOf(numeric::nonempty(numeric::Words{}, word64(*length)))
                : numeric::Known::Unknown;
}

// A Double neither infinite nor NaN, where an op holds it: the condition
// over its bits.
numeric::Known finiteOf(Attribute value) {
  auto real = dyn_cast_or_null<FloatAttr>(value);
  if (!real)
    return numeric::Known::Unknown;
  APInt bits = real.getValue().bitcastToAPInt();
  return knownOf(
      numeric::finite(numeric::Words{}, numeric::Words::of(bits.getZExtValue(), bits.getBitWidth())));
}

} // namespace

//===----------------------------------------------------------------------===//
// The conditions on constants
//===----------------------------------------------------------------------===//

// A constant other than zero.
bool CheckNonzeroOp::holds(FoldAdaptor adaptor) {
  std::optional<APInt> value = keyInteger(adaptor.getValue());
  return value && constantNonzero(*value) == numeric::Known::Holds;
}

bool CheckInBoundsOp::holds(FoldAdaptor adaptor) {
  auto index = dyn_cast_or_null<IntegerAttr>(adaptor.getIndex());
  std::optional<int64_t> length = lengthOf(adaptor.getIndexed());
  return index && length &&
         numeric::inBounds(numeric::Words{}, numeric::wordOf(index), word64(*length)).holds;
}

bool CheckNonemptyOp::holds(FoldAdaptor adaptor) {
  return nonemptyOf(adaptor.getStr()) == numeric::Known::Holds;
}

bool CheckFiniteOp::holds(FoldAdaptor adaptor) {
  return finiteOf(adaptor.getValue()) == numeric::Known::Holds;
}

// Never of a constant: a program's constant handles are null and the
// standard streams, and every handle that holds a string is one the runtime
// gave at run time.
bool CheckHoldsStringOp::holds(FoldAdaptor) { return false; }

bool CheckRangeOp::holds(FoldAdaptor adaptor) {
  auto offset = dyn_cast_or_null<IntegerAttr>(adaptor.getOffset());
  auto count = dyn_cast_or_null<IntegerAttr>(adaptor.getCount());
  auto size = dyn_cast_or_null<IntegerAttr>(adaptor.getSize());
  if (!offset || !count || !size)
    return false;
  return numeric::inRange(numeric::Words{}, numeric::wordOf(offset), numeric::wordOf(count),
                          numeric::wordOf(size))
      .holds;
}

//===----------------------------------------------------------------------===//
// The conditions on intervals and the constants ops hold
//===----------------------------------------------------------------------===//

// Zero is outside the divisor's interval, or is all of it; an Integer's
// interval is its value's (idr::ranges), so the same test decides it,
// but for a constant past i64, which its constant decides. A constant is
// the one interval it is, so it decides a word's as well.
numeric::Known CheckNonzeroOp::decide(ArrayRef<ConstantIntRanges> ranges,
                                      ArrayRef<Attribute> constants) {
  if (std::optional<APInt> value = keyInteger(constants[0]))
    return constantNonzero(*value);
  if (ranges[0].umin().getBitWidth() == 0)
    return numeric::Known::Unknown;
  return numeric::nonzero(numeric::Intervals{}, ranges[0]).known;
}

// The index's interval against the length of a constant string; an
// array's length is no operand's interval, and stays unknown.
numeric::Known CheckInBoundsOp::decide(ArrayRef<ConstantIntRanges> ranges,
                                       ArrayRef<Attribute> constants) {
  std::optional<int64_t> length = lengthOf(constants[1]);
  if (!length)
    return numeric::Known::Unknown;
  numeric::Intervals d;
  return numeric::inBounds(d, ranges[0], d.constant(*length, ranges[0])).known;
}

// A string and a Double have no interval: only a constant decides them.
numeric::Known CheckNonemptyOp::decide(ArrayRef<ConstantIntRanges>,
                                       ArrayRef<Attribute> constants) {
  return nonemptyOf(constants[0]);
}
numeric::Known CheckFiniteOp::decide(ArrayRef<ConstantIntRanges>,
                                     ArrayRef<Attribute> constants) {
  return finiteOf(constants[0]);
}

numeric::Known CheckRangeOp::decide(ArrayRef<ConstantIntRanges> ranges, ArrayRef<Attribute>) {
  return numeric::inRange(numeric::Intervals{}, ranges[0], ranges[1], ranges[2]).known;
}

// A handle's interval says nothing of what its slot holds, but where it is
// one value, a handle the program wrote, which never holds a string (the
// guard's holds): it fails.
numeric::Known CheckHoldsStringOp::decide(ArrayRef<ConstantIntRanges> ranges,
                                          ArrayRef<Attribute>) {
  return ranges[0].getConstantValue() ? numeric::Known::Fails : numeric::Known::Unknown;
}

//===----------------------------------------------------------------------===//
// Folding
//===----------------------------------------------------------------------===//

// The value a guard checks, where its condition holds of its constants.
// Nothing otherwise: a guard that would crash keeps its crash, which the
// e-graph makes a plain crash where its condition is refuted.
OpFoldResult CheckNonzeroOp::fold(FoldAdaptor adaptor) {
  return holds(adaptor) ? OpFoldResult(getValue()) : OpFoldResult();
}
OpFoldResult CheckInBoundsOp::fold(FoldAdaptor adaptor) {
  return holds(adaptor) ? OpFoldResult(getIndex()) : OpFoldResult();
}
OpFoldResult CheckNonemptyOp::fold(FoldAdaptor adaptor) {
  return holds(adaptor) ? OpFoldResult(getStr()) : OpFoldResult();
}
OpFoldResult CheckFiniteOp::fold(FoldAdaptor adaptor) {
  return holds(adaptor) ? OpFoldResult(getValue()) : OpFoldResult();
}
OpFoldResult CheckRangeOp::fold(FoldAdaptor adaptor) {
  return holds(adaptor) ? OpFoldResult(getOffset()) : OpFoldResult();
}
// Never folds: no constant holds a string (holds).
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
