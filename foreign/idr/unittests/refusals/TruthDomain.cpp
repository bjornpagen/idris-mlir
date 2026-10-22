// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An op of inline arithmetic is one template over a numeric domain, and a
// domain's truth is never a bool: over an IR builder a truth is an i1
// value, and an mlir::Value converts to bool, so a template that branched
// on a truth would compile there and lower `-7 div 2` to -3. Two domains
// the same in every respect but what their comparisons give: the one whose
// truth no bool is made from is a domain, the other is refused.

#include "idr/IR/Numeric/Domain.h"

#include <cstdint>

struct Holds {
  bool holds;
};
constexpr bool holds(Holds t) { return t.holds; }
constexpr bool holds(bool t) { return t; }

template <class T>
struct Integers {
  using Value = std::int64_t;
  using Truth = T;
  static constexpr idr::numeric::Overflow overflow = idr::numeric::Overflow::Cannot;

  constexpr Value constant(std::int64_t c, Value) const { return c; }
  constexpr Value add(Value a, Value b) const { return a + b; }
  constexpr Value sub(Value a, Value b) const { return a - b; }
  constexpr Value quotientTowardZero(Value a,
                                     const idr::numeric::SafeDivisor<Integers> &s) const {
    return a / s.value();
  }
  constexpr Value remainderTowardZero(Value a,
                                      const idr::numeric::SafeDivisor<Integers> &s) const {
    return a % s.value();
  }
  constexpr T equal(Value a, Value b) const { return T{a == b}; }
  constexpr T lessSigned(Value a, Value b) const { return T{a < b}; }
  constexpr T both(T t, T u) const { return T{holds(t) && holds(u)}; }
  constexpr Value select(T t, Value a, Value b) const { return holds(t) ? a : b; }
};

static_assert(idr::numeric::Arithmetic<Integers<Holds>>);
// expected-error@+1 {{a truth is never a bool}}
static_assert(idr::numeric::Arithmetic<Integers<bool>>, "a truth is never a bool");
