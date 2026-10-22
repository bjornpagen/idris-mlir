// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The laws the rewrite rules on the inline ops rest on, each stated over
// the meanings themselves (Inline.h): a rule of the specification names its
// law (Spec.Ops.Numeric's Law, printed as `Law`), and the law is checked
// here against the one meaning, exhaustively over 8-bit words when the
// compiler is built (Checks.h). So a rule's two sides are never a second
// statement of an op's arithmetic: the left side is the op, whose meaning
// is the template, and the right side is ops whose meanings are the
// template's or arith's, compared on every 8-bit input.
//
// The families are the one-way, constant-triggered ones our semantics
// creates, which no upstream pattern knows because upstream has no
// Euclidean division and no total shift: a power-of-two divisor is a shift
// or a mask, a negative shift amount turns the shift, a char conversion of
// a char is that char. Integer's two, on the runtime's smalls, are checked
// on the runtime's own domain over a range of values; past the small range
// the law is the runtime's documented semantics, as every law on a
// primitive is.
//
// Freestanding, as Domain.h.
#ifndef IDR_IR_NUMERIC_LAWS_H
#define IDR_IR_NUMERIC_LAWS_H

#include "idr/IR/Numeric/Inline.h"
#include "idr/IR/Numeric/Small.h"
#include "idr/IR/Numeric/Word.h"

#include <cstdint>

namespace idr::numeric {

// The width the laws are checked at exhaustively, and the domain at it.
inline constexpr unsigned lawWidth = 8;

// The 8-bit word whose bits are `bits`.
constexpr Word byte(std::uint64_t bits) { return Words::of(bits, lawWidth); }

// How many inputs a law over bytes is checked on: every byte.
inline constexpr std::uint64_t byteInputs = std::uint64_t{1} << lawWidth;

// Whether `law` holds of every 8-bit dividend or shifted value `a`, for
// every constant the rule admits. One dividend at a time, so each
// static_assert is one bounded evaluation (Checks.h).
template <Law L>
struct LawAt;

// int.divs a 1 ==> a.
template <>
struct LawAt<Law::QuotientByOne> {
  static constexpr std::uint64_t inputs = byteInputs;
  static constexpr bool holds(std::uint64_t a) {
    Words d;
    return euclid<Part::Quotient>(d, byte(a), byte(1)) == byte(a);
  }
};

// int.divs a -1 ==> 0 - a: the least value over -1 wraps to itself, as its
// negation does.
template <>
struct LawAt<Law::QuotientByMinusOne> {
  static constexpr std::uint64_t inputs = byteInputs;
  static constexpr bool holds(std::uint64_t a) {
    Words d;
    return euclid<Part::Quotient>(d, byte(a), d.constant(-1, byte(0))) ==
           d.sub(byte(0), byte(a));
  }
};

// int.mods a 1 ==> 0, int.mods a -1 ==> 0.
template <>
struct LawAt<Law::RemainderByUnit> {
  static constexpr std::uint64_t inputs = byteInputs;
  static constexpr bool holds(std::uint64_t a) {
    Words d;
    return euclid<Part::Remainder>(d, byte(a), byte(1)) == byte(0) &&
           euclid<Part::Remainder>(d, byte(a), d.constant(-1, byte(0))) == byte(0);
  }
};

// int.divs a 2^k ==> int.shrs a k, for 1 <= k < width - 1: Euclidean
// division by a positive divisor is floor division, which the arithmetic
// shift is; truncating division is not.
template <>
struct LawAt<Law::QuotientByPowerOfTwo> {
  static constexpr std::uint64_t inputs = byteInputs;
  static constexpr bool holds(std::uint64_t a) {
    Words d;
    for (unsigned k = 1; k + 1 < lawWidth; ++k)
      if (!(euclid<Part::Quotient>(d, byte(a), byte(std::uint64_t{1} << k)) ==
            shift<Direction::Right, Signedness::Signed>(d, byte(a), byte(k))))
        return false;
    return true;
  }
};

// int.mods a 2^k ==> arith.andi a (2^k - 1), for 1 <= k < width - 1: the
// Euclidean remainder is in [0, 2^k) for a negative dividend too.
template <>
struct LawAt<Law::RemainderByPowerOfTwo> {
  static constexpr std::uint64_t inputs = byteInputs;
  static constexpr bool holds(std::uint64_t a) {
    Words d;
    for (unsigned k = 1; k + 1 < lawWidth; ++k)
      if (!(euclid<Part::Remainder>(d, byte(a), byte(std::uint64_t{1} << k)) ==
            d.bitAnd(byte(a), byte((std::uint64_t{1} << k) - 1))))
        return false;
    return true;
  }
};

// int.mods a (-2^k) ==> arith.andi a (2^k - 1), for 1 <= k < width: the
// remainder depends on the divisor's magnitude only.
template <>
struct LawAt<Law::RemainderByNegativePowerOfTwo> {
  static constexpr std::uint64_t inputs = byteInputs;
  static constexpr bool holds(std::uint64_t a) {
    Words d;
    for (unsigned k = 1; k < lawWidth; ++k)
      if (!(euclid<Part::Remainder>(d, byte(a), d.constant(-(std::int64_t{1} << k), byte(0))) ==
            d.bitAnd(byte(a), byte((std::uint64_t{1} << k) - 1))))
        return false;
    return true;
  }
};

// A shift by 0 is its value, for each of the four shifts.
template <>
struct LawAt<Law::ShiftByZero> {
  static constexpr std::uint64_t inputs = byteInputs;
  static constexpr bool holds(std::uint64_t a) {
    Words d;
    Word v = byte(a), z = byte(0);
    return shift<Direction::Left, Signedness::Signed>(d, v, z) == v &&
           shift<Direction::Left, Signedness::Unsigned>(d, v, z) == v &&
           shift<Direction::Right, Signedness::Signed>(d, v, z) == v &&
           shift<Direction::Right, Signedness::Unsigned>(d, v, z) == v;
  }
};

// int.shls a (-k) ==> int.shrs a k and int.shrs a (-k) ==> int.shls a k,
// for 0 < k < width: a negative amount turns a signed shift.
template <>
struct LawAt<Law::ShiftByNegative> {
  static constexpr std::uint64_t inputs = byteInputs;
  static constexpr bool holds(std::uint64_t a) {
    Words d;
    for (unsigned k = 1; k < lawWidth; ++k) {
      Word minus = d.constant(-static_cast<std::int64_t>(k), byte(0)), plus = byte(k);
      if (!(shift<Direction::Left, Signedness::Signed>(d, byte(a), minus) ==
            shift<Direction::Right, Signedness::Signed>(d, byte(a), plus)))
        return false;
      if (!(shift<Direction::Right, Signedness::Signed>(d, byte(a), minus) ==
            shift<Direction::Left, Signedness::Signed>(d, byte(a), plus)))
        return false;
    }
    return true;
  }
};

// int.to_char_x (int.to_char_y a) ==> int.to_char_y a: a char is a scalar
// value, non-negative in its 32 bits, so testing it again keeps it, read
// either way.
template <>
struct LawAt<Law::CharOfChar> {
  static constexpr std::uint64_t inputs = byteInputs;
  static constexpr bool holds(std::uint64_t a) {
    Words d;
    auto again = [&](Word c) {
      return toChar<Signedness::Signed>(d, c) == c && toChar<Signedness::Unsigned>(d, c) == c;
    };
    return again(toChar<Signedness::Signed>(d, byte(a))) &&
           again(toChar<Signedness::Unsigned>(d, byte(a)));
  }
};

// The smalls the Integer laws are checked on: every value within `span` of
// zero and of each end of the small range, the runtime's 63-bit integers.
inline constexpr std::int64_t smallSpan = 64;
inline constexpr std::int64_t smallLeast = -(std::int64_t{1} << 62);
inline constexpr std::int64_t smallGreatest = (std::int64_t{1} << 62) - 1;
inline constexpr std::uint64_t smallInputs = 3 * 2 * smallSpan;

// The i-th small checked: `a` indexes the three neighbourhoods in turn.
constexpr std::int64_t smallSample(std::uint64_t a) {
  auto i = static_cast<std::int64_t>(a % (2 * smallSpan)) - smallSpan;
  switch (a / (2 * smallSpan) % 3) {
  case 0:
    return i;
  case 1:
    return smallLeast + smallSpan + i;
  default:
    return smallGreatest - smallSpan + i;
  }
}

// idr.big.mod a 2^k ==> idr.big.and a (2^k - 1), for 1 <= k < 62, on the
// smalls: the remainder of a two's complement integer by a power of two is
// its low bits.
template <>
struct LawAt<Law::IntegerRemainderByPowerOfTwo> {
  static constexpr std::uint64_t inputs = smallInputs;
  static constexpr bool holds(std::uint64_t a) {
    Smalls d;
    std::int64_t x = smallSample(a);
    for (unsigned k = 1; k < 62; ++k) {
      std::int64_t p = std::int64_t{1} << k;
      if (euclid<Part::Remainder>(d, x, p) != (x & (p - 1)))
        return false;
    }
    return true;
  }
};

// idr.big.div a 2^k ==> idr.big.shr a k, for 1 <= k < 62, on the smalls:
// floor division by a power of two is the arithmetic shift.
template <>
struct LawAt<Law::IntegerQuotientByPowerOfTwo> {
  static constexpr std::uint64_t inputs = smallInputs;
  static constexpr bool holds(std::uint64_t a) {
    Smalls d;
    std::int64_t x = smallSample(a);
    for (unsigned k = 1; k < 62; ++k)
      if (euclid<Part::Quotient>(d, x, std::int64_t{1} << k) != (x >> k))
        return false;
    return true;
  }
};

} // namespace idr::numeric

#endif // IDR_IR_NUMERIC_LAWS_H
