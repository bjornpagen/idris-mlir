// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The bounds of bigs and naturals, the ranges of values never negative, the
// range a type proves, and the range of a value known to be none of some
// keys.

#include "idr/IR/Ranges.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/Support/CheckedArithmetic.h"

#include <algorithm>
#include <concepts>
#include <cstdint>

using namespace mlir;

namespace idr::ranges {

namespace {

std::optional<int64_t> inside(std::optional<int64_t> v) noexcept {
  if (v && *v >= IDRIS_RT_SMALL_MIN && *v <= IDRIS_RT_SMALL_MAX)
    return v;
  return std::nullopt;
}

// Both bounds known: their sum or difference cannot overflow an i64, since
// each is inside the small range.
std::optional<int64_t> plus(std::optional<int64_t> x, std::optional<int64_t> y) noexcept {
  if (x && y)
    return *x + *y;
  return std::nullopt;
}

std::optional<int64_t> minus(std::optional<int64_t> x, std::optional<int64_t> y) noexcept {
  if (x && y)
    return *x - *y;
  return std::nullopt;
}

// One view's ends, [lo, hi] in its order.
struct Ends {
  APInt lo, hi;
};

// The ends with each of `keys` cut from the end it is, inward while the
// next key in the view's order `before` is the new end, never past the one
// value left.
template <typename Before>
  requires std::strict_weak_order<Before, const APInt &, const APInt &>
Ends cut(Ends ends, SmallVector<APInt> keys, Before before) {
  llvm::sort(keys, before);
  for (const APInt &key : keys) {
    if (before(key, ends.lo))
      continue;
    if (key != ends.lo || !before(ends.lo, ends.hi))
      break;
    ++ends.lo;
  }
  for (const APInt &key : llvm::reverse(keys)) {
    if (before(ends.hi, key))
      continue;
    if (key != ends.hi || !before(ends.lo, ends.hi))
      break;
    --ends.hi;
  }
  return ends;
}

} // namespace

Bounds bounded(std::optional<int64_t> lo, std::optional<int64_t> hi) noexcept {
  return {inside(lo), inside(hi)};
}

Bounds natural() noexcept { return {0, std::nullopt}; }

Bounds boundsOf(const ConstantIntRanges &range) noexcept {
  if (range.smin().getBitWidth() != 64)
    return {};
  return bounded(range.smin().getSExtValue(), range.smax().getSExtValue());
}

Bounds add(Bounds a, Bounds b) noexcept { return bounded(plus(a.lo, b.lo), plus(a.hi, b.hi)); }

Bounds sub(Bounds a, Bounds b) noexcept { return bounded(minus(a.lo, b.hi), minus(a.hi, b.lo)); }

// With every bound known, the least and greatest of the corners' products;
// with two non-negative factors, at least their lower bounds' product.
Bounds mul(Bounds a, Bounds b) noexcept {
  if (a.fits() && b.fits()) {
    std::optional<int64_t> corners[] = {
        llvm::checkedMul(*a.lo, *b.lo), llvm::checkedMul(*a.lo, *b.hi),
        llvm::checkedMul(*a.hi, *b.lo), llvm::checkedMul(*a.hi, *b.hi)};
    if (llvm::all_of(corners, [](std::optional<int64_t> c) { return c.has_value(); })) {
      auto [lo, hi] = std::minmax({*corners[0], *corners[1], *corners[2], *corners[3]});
      return bounded(lo, hi);
    }
  }
  if (a.lo && b.lo && *a.lo >= 0 && *b.lo >= 0)
    return bounded(llvm::checkedMul(*a.lo, *b.lo), std::nullopt);
  return {};
}

Bounds ofSmall(const ConstantIntRanges &range) noexcept {
  int64_t lo = IDRIS_RT_SMALL_MIN, hi = IDRIS_RT_SMALL_MAX;
  if (range.smin().getBitWidth() == 64) {
    lo = std::clamp(range.smin().getSExtValue(), lo, hi);
    hi = std::clamp(range.smax().getSExtValue(), lo, hi);
  }
  return {lo, hi};
}

Bounds ofInteger(const ConstantIntRanges &range, numeric::Signedness signedness) noexcept {
  unsigned width = range.smin().getBitWidth();
  if (width == 0 || width > 64)
    return {};
  if (signedness == numeric::Signedness::Signed)
    return bounded(range.smin().getSExtValue(), range.smax().getSExtValue());
  // An unsigned 64-bit value above INT64_MAX is outside the small range.
  auto unsignedBound = [](const APInt &v) -> std::optional<int64_t> {
    if (v.getZExtValue() > static_cast<uint64_t>(INT64_MAX))
      return std::nullopt;
    return static_cast<int64_t>(v.getZExtValue());
  };
  return bounded(unsignedBound(range.umin()), unsignedBound(range.umax()));
}

ConstantIntRanges rangeOf(Bounds bounds) noexcept {
  return ConstantIntRanges::fromSigned(
      APInt(64, static_cast<uint64_t>(bounds.lo.value_or(INT64_MIN)), /*isSigned=*/true),
      APInt(64, static_cast<uint64_t>(bounds.hi.value_or(INT64_MAX)), /*isSigned=*/true));
}

ConstantIntRanges nonNegative(unsigned width, uint64_t min, uint64_t max) {
  return ConstantIntRanges::fromUnsigned(APInt(width, min), APInt(width, max));
}

// A big, a natural and a numeral prove more than their storage; any other
// value has upstream's maximum range (IntegerValueRange::getMaxRange), so a
// seed joins every range an op infers at the width the op infers it.
IntegerValueRange ofType(Type type) {
  switch (numericReadingOf(type)) {
  case NumericReading::Integer:
    return IntegerValueRange(rangeOf({}));
  case NumericReading::Natural:
    return IntegerValueRange(rangeOf(natural()));
  case NumericReading::Bits:
    break;
  }
  // A numeral whose indices fix its bound is a word of its layout's width,
  // up to the largest value they allow, which the type kept when it was
  // made (`#Fin[3]` 0 to 2, so no bounds check on an index of one is
  // built). A data type of any other layout holds no integer.
  if (DataType data = dataTypeOf(type))
    if (std::optional<uint64_t> largest = data.numeralBound())
      return IntegerValueRange(nonNegative(families::numberBits(data.layout()), 0, *largest));
  unsigned width = ConstantIntRanges::getStorageBitwidth(unrestricted(type));
  // A width-0 APInt has no sign bit, so upstream stores the range of a value
  // that holds no integer as the one width-0 value in all four bounds.
  if (width == 0)
    return IntegerValueRange(ConstantIntRanges::constant(APInt::getZero(0)));
  return IntegerValueRange(ConstantIntRanges::maxRange(width));
}

// The signed view is cut for every value; the unsigned only for a word, the
// one reading with bits for it to bound: a big's range is of the integer,
// its unsigned view only what the signed one implies. A key wider than the
// range's width is no value of it, and a big's or a natural's key past the
// small range is no bound of it, since a bound there is none: neither cuts.
ConstantIntRanges excluding(Type type, const ConstantIntRanges &range, ArrayRef<APInt> keys) {
  unsigned width = range.smin().getBitWidth();
  // A value that holds no integer has no bounds to cut.
  if (width == 0)
    return range;
  NumericReading reading = numericReadingOf(type);
  SmallVector<APInt> atWidth;
  for (const APInt &key : keys) {
    if (key.getSignificantBits() > width)
      continue;
    APInt at = key.sextOrTrunc(width);
    if (reading != NumericReading::Bits && !inside(at.trySExtValue()))
      continue;
    atWidth.push_back(std::move(at));
  }
  Ends s = cut({range.smin(), range.smax()}, atWidth,
               [](const APInt &a, const APInt &b) { return a.slt(b); });
  ConstantIntRanges refined = ConstantIntRanges::fromSigned(s.lo, s.hi).intersection(range);
  switch (reading) {
  case NumericReading::Integer:
  case NumericReading::Natural:
    break;
  case NumericReading::Bits: {
    Ends u = cut({range.umin(), range.umax()}, std::move(atWidth),
                 [](const APInt &a, const APInt &b) { return a.ult(b); });
    refined = refined.intersection(ConstantIntRanges::fromUnsigned(u.lo, u.hi));
    break;
  }
  }
  // A range all of whose values are keys has none left once cut, which an
  // interval cannot hold: no value reaches that default, and its range
  // stays as it was.
  if (refined.umin().ugt(refined.umax()) || refined.smin().sgt(refined.smax()))
    return range;
  return refined;
}

void carried(Value result, const IntegerValueRange &range, SetIntLatticeFn setResultRange) {
  if (range.isUninitialized())
    return;
  IntegerValueRange any = ofType(result.getType());
  bool sameWidth = range.getValue().umin().getBitWidth() == any.getValue().umin().getBitWidth();
  setResultRange(result, sameWidth ? range : any);
}

} // namespace idr::ranges
