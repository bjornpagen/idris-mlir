// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops on Integers and naturals: their ranges, from their bounds, each
// within the range its type proves (idr::ranges::ofType); the conditions of
// the folds a runtime function's own value would not keep (a shift whose
// constant would be too large to make, the predecessor of zero, which no
// natural is); and the fold of the one op with no runtime form, a natural
// as an Integer. Every other op folds through its runtime function
// (Fold.h). And the natural's type, linked to its index term.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Families/Terms.h"
#include "idr/IR/Fold.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ranges.h"

#include "mlir/Interfaces/Utils/InferIntRangeCommon.h"

#include <algorithm>
#include <limits>

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
void NatPredOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
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
void BigFromSintOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                      SetIntRangeFn setResultRange) {
  setBounds(getResult(), idr::ranges::ofInteger(ranges[0], numeric::Signedness::Signed),
            setResultRange);
}

void BigFromUintOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                      SetIntRangeFn setResultRange) {
  setBounds(getResult(), idr::ranges::ofInteger(ranges[0], numeric::Signedness::Unsigned),
            setResultRange);
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

//===----------------------------------------------------------------------===//
// Folds
//===----------------------------------------------------------------------===//

namespace {

// Whether shifting the constant `value` by `amount`, left when `Left`, the
// other way when the amount is negative, makes a constant no larger than
// the program already holds. A shift toward zero, or of 0, shrinks or keeps
// its operand. One away from zero folds only to a small, which the big's
// encoding holds in its word, so the fold makes no static datum; a larger
// result stays the op, whose runtime makes it where evaluation reaches it,
// and the compiler never computes a constant of a size the program's text
// does not bound.
template <numeric::Direction Dir>
bool smallEnough(ArrayRef<Attribute> constants) {
  auto value = dyn_cast_or_null<BigAttr>(constants[0]);
  auto amount = dyn_cast_or_null<BigAttr>(constants[1]);
  if (!value || !amount)
    return false;
  const APInt &places = amount.getValue();
  bool awayFromZero = (Dir == numeric::Direction::Left) != places.isNegative();
  if (!awayFromZero || value.getValue().isZero())
    return true;
  // A nonzero integer shifted past an i64's digits is no i64, so no small.
  std::optional<uint64_t> count = places.abs().tryZExtValue();
  if (!count || *count > std::numeric_limits<int64_t>::digits)
    return false;
  const APInt &operand = value.getValue();
  std::optional<int64_t> shifted =
      operand.sext(operand.getBitWidth() + static_cast<unsigned>(*count))
          .shl(static_cast<unsigned>(*count))
          .trySExtValue();
  return shifted && idr::ranges::bounded(*shifted, *shifted).fits();
}

} // namespace

bool BigShlOp::foldable(ArrayRef<Attribute> constants) {
  return smallEnough<numeric::Direction::Left>(constants);
}
bool BigShrOp::foldable(ArrayRef<Attribute> constants) {
  return smallEnough<numeric::Direction::Right>(constants);
}

// Zero has no predecessor: a constant zero is on a path the match before
// it excludes, and stays as it is.
bool NatPredOp::foldable(ArrayRef<Attribute> constants) {
  auto value = dyn_cast_or_null<BigAttr>(constants[0]);
  return value && !value.getValue().isZero();
}

// The constant is the same value under the other type, which the constant
// that materializes it takes from the op's result.
OpFoldResult NatToBigOp::fold(FoldAdaptor adaptor) {
  return dyn_cast_or_null<BigAttr>(adaptor.getValue());
}

//===----------------------------------------------------------------------===//
// The natural's type
//===----------------------------------------------------------------------===//

// `!idr.nat<t>`: the natural linked to the index term `t`, written as the
// families write a term, `_` where no term is known.
Type NatType::parse(AsmParser &parser) {
  SmallVector<families::TermNode> index;
  if (parser.parseLess() || families::parseTerms(parser, 1, index, nullptr) ||
      parser.parseGreater())
    return {};
  return getChecked([&] { return parser.emitError(parser.getNameLoc()); }, parser.getContext(),
                    index);
}

void NatType::print(AsmPrinter &printer) const {
  printer << '<';
  families::printTerms(printer, getIndex(), 1, Attribute());
  printer << '>';
}

// One whole term: a bytecode read writes nodes no builder wrote, and every
// walk of the term trusts its extent.
LogicalResult NatType::verify(function_ref<InFlightDiagnostic()> emitError,
                              ArrayRef<families::TermNode> index) {
  if (families::countTerms(index) != std::optional<size_t>(1))
    return emitError() << "expects a natural linked to one index term";
  return success();
}
