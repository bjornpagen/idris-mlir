// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ranges of the ops on bigs and naturals, from their bounds, each
// within the range its type proves (idr::ranges::ofType).

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ranges.h"

#include "mlir/Interfaces/Utils/InferIntRangeCommon.h"

#include <algorithm>

using namespace mlir;
using namespace idr;

using idr::ranges::Bounds;

namespace {

// Sets the range of `result` to `bounds`, within the range its type proves
// at any grade: a natural is never negative, whatever its operands' ranges
// say.
void setBounds(Value result, Bounds bounds, SetIntRangeFn setResultRange) {
  setResultRange(result, idr::ranges::rangeOf(bounds).intersection(
                             idr::ranges::ofType(result.getType()).getValue()));
}

// The bounds of `operand`, whose range is `range`, within the range its type
// proves at any grade.
Bounds operandBounds(Value operand, const ConstantIntRanges &range) {
  return idr::ranges::boundsOf(
      range.intersection(idr::ranges::ofType(operand.getType()).getValue()));
}

} // namespace

// A constant big or natural has its value's range.
void ConstantOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  // Any other constant is not an integer: it has no range to state.
  auto big = dyn_cast<BigAttr>(getValue());
  if (!big || !isa<BigType, NatType>(unrestricted(getType())))
    return;
  // A value outside i64 is outside the small range too.
  Bounds bounds;
  if (std::optional<int64_t> value = big.getValue().trySExtValue())
    bounds = idr::ranges::bounded(*value, *value);
  setBounds(getResult(), bounds, setResultRange);
}

void BigAddOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                 SetIntRangeFn setResultRange) {
  setBounds(getResult(),
            idr::ranges::add(idr::ranges::boundsOf(ranges[0]), idr::ranges::boundsOf(ranges[1])),
            setResultRange);
}

void BigSubOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                 SetIntRangeFn setResultRange) {
  setBounds(getResult(),
            idr::ranges::sub(idr::ranges::boundsOf(ranges[0]), idr::ranges::boundsOf(ranges[1])),
            setResultRange);
}

void BigMulOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                 SetIntRangeFn setResultRange) {
  setBounds(getResult(),
            idr::ranges::mul(idr::ranges::boundsOf(ranges[0]), idr::ranges::boundsOf(ranges[1])),
            setResultRange);
}

// The operand is not zero, so it is at least 1 and its predecessor at
// least 0.
void BigPredOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                  SetIntRangeFn setResultRange) {
  Bounds a = idr::ranges::boundsOf(ranges[0]);
  int64_t lo = std::max<int64_t>(a.lo.value_or(1), 1) - 1;
  std::optional<int64_t> hi;
  if (a.hi)
    hi = std::max(*a.hi - 1, lo);
  setBounds(getResult(), idr::ranges::bounded(lo, hi), setResultRange);
}

void NatToBigOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                   SetIntRangeFn setResultRange) {
  setBounds(getResult(), operandBounds(getValue(), ranges[0]), setResultRange);
}

// The clamp: a negative Integer is 0.
void NatFromBigOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                     SetIntRangeFn setResultRange) {
  Bounds a = idr::ranges::boundsOf(ranges[0]);
  std::optional<int64_t> hi;
  if (a.hi)
    hi = std::max<int64_t>(*a.hi, 0);
  setBounds(getResult(), idr::ranges::bounded(std::max<int64_t>(a.lo.value_or(0), 0), hi),
            setResultRange);
}

void BigCmpOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                 SetIntRangeFn setResultRange) {
  auto operand = [&](unsigned i) {
    return idr::ranges::rangeOf(operandBounds(getOperand(i), ranges[i]));
  };
  // The comparison of the words, whose predicate is arith's, which the
  // range machinery's copies in order.
  auto predicate =
      static_cast<intrange::CmpPredicate>(idr::layout::signedPredicate(getPredicate()));
  // An unbounded side is the extreme of i64, which orders below or above
  // every bound, so a comparison decided on these ranges is decided.
  std::optional<bool> decided = intrange::evaluatePred(predicate, operand(0), operand(1));
  if (!decided) {
    setResultRange(getResult(), ConstantIntRanges::maxRange(1));
    return;
  }
  setResultRange(getResult(), ConstantIntRanges::constant(APInt(1, *decided ? 1 : 0)));
}

// The integer's bounds, read as the op's signedness says.
void BigFromSIntOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                      SetIntRangeFn setResultRange) {
  setBounds(getResult(), idr::ranges::ofInteger(ranges[0], isSigned), setResultRange);
}

void BigFromUIntOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                      SetIntRangeFn setResultRange) {
  setBounds(getResult(), idr::ranges::ofInteger(ranges[0], isSigned), setResultRange);
}

// A small is its word, which the op's writer proved inside the small range.
void BigSmallOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                   SetIntRangeFn setResultRange) {
  setBounds(getResult(), idr::ranges::ofSmall(ranges[0]), setResultRange);
}

// The value, wrapped to the width: exact when every value fits the width.
void BigToIntOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                   SetIntRangeFn setResultRange) {
  Bounds a = operandBounds(getValue(), ranges[0]);
  unsigned width = getType().getIntOrFloatBitWidth();
  if (a.fits()) {
    APInt lo(64, static_cast<uint64_t>(*a.lo), true), hi(64, static_cast<uint64_t>(*a.hi), true);
    if (lo.isSignedIntN(width) && hi.isSignedIntN(width)) {
      setResultRange(getResult(),
                     ConstantIntRanges::fromSigned(lo.trunc(width), hi.trunc(width)));
      return;
    }
    if (!lo.isNegative() && hi.isIntN(width)) {
      setResultRange(getResult(),
                     ConstantIntRanges::fromUnsigned(lo.trunc(width), hi.trunc(width)));
      return;
    }
  }
  setResultRange(getResult(), ConstantIntRanges::maxRange(width));
}
