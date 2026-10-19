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
// type proves. The small range, the values a big holds in its word, is the
// runtime's: IDRIS_RT_SMALL_MIN to IDRIS_RT_SMALL_MAX.
#ifndef IDR_IR_RANGES_H
#define IDR_IR_RANGES_H

#include "mlir/Interfaces/InferIntRangeInterface.h"

#include "idris_rt.h"

#include <cstdint>
#include <optional>

namespace idr::ranges {

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

// The range every value of `type` is in, whatever its grade, as the type
// alone proves it: at least 0 for a natural, none for a big; for any other
// type upstream's maximum range of a value of it (getMaxRange): its storage
// width's whole range for an integer, an index or a shaped value of them,
// and the initialized width-0 range for a type that holds no integer (a
// box, a string), which leaves no op's inference without its operands.
mlir::IntegerValueRange ofType(mlir::Type type);

// The range an op that only changes its operand's grade gives `result`
// (::idr::ResultCarriesOperand: a view, a share, a linear position): the
// operand's `range`, once it has one, at the width the result's type proves
// its range at (ofType, which ignores the grade). A range of another width,
// the one upstream gives a value whose type is no integer, stands for no
// value it knows of: the result then has every value its type allows.
void carried(mlir::Value result, const mlir::IntegerValueRange &range,
             mlir::SetIntLatticeFn setResultRange);

} // namespace idr::ranges

#endif // IDR_IR_RANGES_H
