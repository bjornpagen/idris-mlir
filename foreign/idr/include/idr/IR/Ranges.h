// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The integer ranges of bigs and naturals, which the dialect's range hooks
// state and idr-narrow reads. Integer range analysis carries them as it
// carries any integer's: 64-bit signed bounds, here on the value a big
// stands for, not on its tagged word. A bound inside the small range is a
// bound; the extremes of i64 stand for none. So a range whose bounds are
// both inside fits a small, and "may not fit a small" is the top, which
// every big the analysis cannot see computed starts at. Integer and Nat
// share the machinery: a natural only adds the lower bound 0, which its
// type proves.
#ifndef IDR_IR_RANGES_H
#define IDR_IR_RANGES_H

#include "mlir/Interfaces/InferIntRangeInterface.h"

#include <cstdint>
#include <optional>

namespace idr::ranges {

// The small range: the values a big holds in its word.
inline constexpr int64_t smallMin = -(int64_t{1} << 62);
inline constexpr int64_t smallMax = (int64_t{1} << 62) - 1;

// The bounds of a value, where no bound is none that way. Each bound is
// inside the small range.
struct Bounds {
  std::optional<int64_t> lo, hi;

  // Every value fits a small, so the sum, difference or product of two
  // such values is an i64 that cannot overflow.
  bool fits() const noexcept { return lo && hi; }
};

// Keeps each bound only when it is inside the small range.
Bounds bounded(std::optional<int64_t> lo, std::optional<int64_t> hi) noexcept;

// What a natural nothing else bounds is: at least 0.
Bounds natural() noexcept;

// The bounds a range states. A range of another width, as MLIR gives a
// value that is not an integer, states none.
Bounds boundsOf(const mlir::ConstantIntRanges &range) noexcept;

// The bounds of a sum, a difference and a product.
Bounds add(Bounds a, Bounds b) noexcept;
Bounds sub(Bounds a, Bounds b) noexcept;
Bounds mul(Bounds a, Bounds b) noexcept;

// The bounds of an integer operand of range `range`, read as `isSigned`
// says.
Bounds ofInteger(const mlir::ConstantIntRanges &range, bool isSigned) noexcept;

// The 64-bit range of `bounds`.
mlir::ConstantIntRanges rangeOf(Bounds bounds) noexcept;

// A range of `width`-bit values, all non-negative: the ops whose results
// are never negative (a tag, a character, a byte, a length) state it so.
mlir::ConstantIntRanges nonNegative(unsigned width, uint64_t min, uint64_t max);

} // namespace idr::ranges

#endif // IDR_IR_RANGES_H
