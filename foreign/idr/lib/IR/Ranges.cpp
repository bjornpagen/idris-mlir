// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The bounds of bigs and naturals, and the ranges of values never negative.

#include "idr/IR/Ranges.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/CheckedArithmetic.h"

#include <algorithm>
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

Bounds ofInteger(const ConstantIntRanges &range, bool isSigned) noexcept {
  unsigned width = range.smin().getBitWidth();
  if (width == 0 || width > 64)
    return {};
  if (isSigned)
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

} // namespace idr::ranges
