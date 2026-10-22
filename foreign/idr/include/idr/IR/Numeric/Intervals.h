// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Integer intervals, the domain an inline op's ranges are computed over:
// a value is upstream's ConstantIntRanges, and every operation is upstream's
// transfer function for the arith op it stands for (intrange::infer*), so a
// meaning instantiated here gives the op's InferIntRangeInterface answer and
// the e-graph's interval analysis, with no range rule of ours beside it. A
// truth is known to hold, known to fail, or unknown; a select on an unknown
// truth is the union of both sides.
#ifndef IDR_IR_NUMERIC_INTERVALS_H
#define IDR_IR_NUMERIC_INTERVALS_H

#include "idr/IR/Numeric/Domain.h"

#include "mlir/Interfaces/InferIntRangeInterface.h"

#include <cstdint>
#include <optional>

namespace idr::numeric {

// What intervals know of a truth: that it holds, that it fails, or
// nothing. A guard whose condition is known to hold is proved; one known
// to fail always crashes.
enum class Known : unsigned char { Holds, Fails, Unknown };

struct KnownTruth {
  Known known;
};

struct Intervals {
  using Value = mlir::ConstantIntRanges;
  using Truth = KnownTruth;
  static constexpr Overflow overflow = Overflow::Wraps;

  unsigned width(const Value &a) const;
  Value constant(std::int64_t c, const Value &like) const;
  Value least(const Value &like) const;

  Value add(const Value &a, const Value &b) const;
  Value sub(const Value &a, const Value &b) const;
  Value bitAnd(const Value &a, const Value &b) const;
  Value quotientTowardZero(const Value &a, const SafeDivisor<Intervals> &s) const;
  Value remainderTowardZero(const Value &a, const SafeDivisor<Intervals> &s) const;
  Value shiftLeft(const Value &a, const BelowWidth<Intervals> &n) const;
  Value shiftRightArithmetic(const Value &a, const BelowWidth<Intervals> &n) const;
  Value shiftRightLogical(const Value &a, const BelowWidth<Intervals> &n) const;
  Value extendSigned(const Value &a, unsigned width) const;
  Value extendUnsigned(const Value &a, unsigned width) const;
  Value truncate(const Value &a, unsigned width) const;

  KnownTruth equal(const Value &a, const Value &b) const;
  KnownTruth lessSigned(const Value &a, const Value &b) const;
  KnownTruth lessUnsigned(const Value &a, const Value &b) const;
  KnownTruth both(KnownTruth t, KnownTruth u) const;
  KnownTruth either(KnownTruth t, KnownTruth u) const;
  KnownTruth negation(KnownTruth t) const;
  Value select(KnownTruth t, const Value &a, const Value &b) const;
};

static_assert(Domain<Intervals>);

} // namespace idr::numeric

#endif // IDR_IR_NUMERIC_INTERVALS_H
