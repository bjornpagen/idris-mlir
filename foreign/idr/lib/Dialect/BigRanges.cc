// The ranges of the ops on bigs and naturals (idr.ranges), and the
// verifier of the one op that may make a natural of an integer.

#include "idr/Idr.h"

#include "mlir/Interfaces/Utils/InferIntRangeCommon.h"

#include <algorithm>

import idr.ranges;

using namespace mlir;
using namespace idr;

namespace {

using idr::ranges::Bounds;

// A natural is never negative, whatever its operands' ranges say.
Bounds ofType(Bounds bounds, Type type) {
  if (isa<NatType>(type) && (!bounds.lo || *bounds.lo < 0))
    bounds.lo = 0;
  return bounds;
}

void setBounds(Value result, Bounds bounds, SetIntRangeFn setResultRange) {
  setResultRange(result, idr::ranges::rangeOf(ofType(bounds, result.getType())));
}

} // namespace

void ConstantOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  // Any other constant is not an integer: it has no range to state.
  auto big = dyn_cast<BigAttr>(getValue());
  if (!big || !isa<BigType, NatType>(unrestricted(getType())))
    return;
  int64_t value = 0;
  // A value outside i64 is outside the small range too.
  Bounds bounds;
  if (!big.getValue().getAsInteger(10, value))
    bounds = idr::ranges::bounded(value, value);
  setResultRange(getResult(), idr::ranges::rangeOf(ofType(bounds, unrestricted(getType()))));
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
  setBounds(getResult(), ofType(idr::ranges::boundsOf(ranges[0]), getValue().getType()),
            setResultRange);
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
    return idr::ranges::rangeOf(
        ofType(idr::ranges::boundsOf(ranges[i]), getOperand(i).getType()));
  };
  intrange::CmpPredicate predicate = intrange::CmpPredicate::eq;
  switch (getPredicate()) {
  case CmpPredicate::eq:
    predicate = intrange::CmpPredicate::eq;
    break;
  case CmpPredicate::lt:
    predicate = intrange::CmpPredicate::slt;
    break;
  case CmpPredicate::lte:
    predicate = intrange::CmpPredicate::sle;
    break;
  case CmpPredicate::gt:
    predicate = intrange::CmpPredicate::sgt;
    break;
  case CmpPredicate::gte:
    predicate = intrange::CmpPredicate::sge;
    break;
  }
  // An unbounded side is the extreme of i64, which orders below or above
  // every bound, so a comparison decided on these ranges is decided.
  std::optional<bool> decided = intrange::evaluatePred(predicate, operand(0), operand(1));
  if (!decided) {
    setResultRange(getResult(), ConstantIntRanges::maxRange(1));
    return;
  }
  setResultRange(getResult(), ConstantIntRanges::constant(APInt(1, *decided ? 1 : 0)));
}

void BigFromIntOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                     SetIntRangeFn setResultRange) {
  setBounds(getResult(), idr::ranges::ofInteger(ranges[0], getIsSigned()), setResultRange);
}

void BigSmallOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                   SetIntRangeFn setResultRange) {
  setBounds(getResult(), idr::ranges::ofInteger(ranges[0], /*isSigned=*/true), setResultRange);
}

// The value, wrapped to the width: exact when every value fits the width.
void BigToIntOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                   SetIntRangeFn setResultRange) {
  Bounds a = ofType(idr::ranges::boundsOf(ranges[0]), getValue().getType());
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

LogicalResult BigFromIntOp::verify() {
  if (isa<NatType>(getType()) && getIsSigned())
    return emitOpError("makes a natural of a signed integer, which may be negative");
  return success();
}
