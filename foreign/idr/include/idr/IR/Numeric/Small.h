// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's small Integers, the domain of its small path of `div` and
// `mod`: a small is a 63-bit integer held in an int64_t, so no quotient of
// two smalls overflows 64 bits. The least small over -1 is 2^62, which is
// no small but is an int64_t, and the runtime gives it back as a large
// Integer: this domain cannot overflow, where a fixed-width word wraps, so
// the runtime's path pays no test for the case (Overflow::Cannot).
//
// Freestanding, as Domain.h: the runtime includes it.
#ifndef IDR_IR_NUMERIC_SMALL_H
#define IDR_IR_NUMERIC_SMALL_H

#include "idr/IR/Numeric/Domain.h"

#include <cstdint>

namespace idr::numeric {

// A truth of smalls: combined and selected on, never a bool.
struct SmallTruth {
  bool holds;
};

struct Smalls {
  using Value = std::int64_t;
  using Truth = SmallTruth;
  static constexpr Overflow overflow = Overflow::Cannot;

  constexpr std::int64_t constant(std::int64_t c, std::int64_t) const { return c; }
  constexpr std::int64_t add(std::int64_t a, std::int64_t b) const { return a + b; }
  constexpr std::int64_t sub(std::int64_t a, std::int64_t b) const { return a - b; }
  constexpr std::int64_t quotientTowardZero(std::int64_t a, const SafeDivisor<Smalls> &s) const {
    return a / s.value();
  }
  constexpr std::int64_t remainderTowardZero(std::int64_t a,
                                             const SafeDivisor<Smalls> &s) const {
    return a % s.value();
  }
  constexpr SmallTruth equal(std::int64_t a, std::int64_t b) const { return {a == b}; }
  constexpr SmallTruth lessSigned(std::int64_t a, std::int64_t b) const { return {a < b}; }
  constexpr SmallTruth both(SmallTruth t, SmallTruth u) const { return {t.holds && u.holds}; }
  constexpr std::int64_t select(SmallTruth t, std::int64_t a, std::int64_t b) const {
    return t.holds ? a : b;
  }
};

static_assert(Arithmetic<Smalls>);

} // namespace idr::numeric

#endif // IDR_IR_NUMERIC_SMALL_H
