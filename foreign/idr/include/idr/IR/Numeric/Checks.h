// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The meanings of the inline ops, checked when the compiler is built: their
// edge cases named one by one, Euclid's definition and the shifts' against
// multiplication and division over every pair of 8-bit words, and every
// law a rule of the specification names (Laws.h). Included by one unit of
// the compiler (lib/IR/Ops/Laws.cpp), so a meaning that changes and breaks
// one of these does not build on any target.
//
// Each exhaustive check is one static_assert per 8-bit input, so no single
// constant evaluation exceeds the compiler's step limit: a check over every
// pair at once would.
//
// Freestanding, as Domain.h.
#ifndef IDR_IR_NUMERIC_CHECKS_H
#define IDR_IR_NUMERIC_CHECKS_H

#include "idr/IR/Numeric/Laws.h"

#include <bit>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <utility>

namespace idr::numeric::checks {

constexpr Word w8(std::int64_t v) { return Words::of(static_cast<std::uint64_t>(v), 8); }
constexpr Word w32(std::int64_t v) { return Words::of(static_cast<std::uint64_t>(v), 32); }
constexpr Word w64(std::int64_t v) { return Words::of(static_cast<std::uint64_t>(v), 64); }

template <Part P>
constexpr Word div8(std::int64_t a, std::int64_t b) {
  return euclid<P>(Words{}, w8(a), w8(b));
}
constexpr bool euclid8(std::int64_t a, std::int64_t b, std::int64_t q, std::int64_t r) {
  return div8<Part::Quotient>(a, b) == w8(q) && div8<Part::Remainder>(a, b) == w8(r);
}

// Euclidean division, by hand.
static_assert(euclid8(-7, 2, -4, 1));
static_assert(euclid8(7, -2, -3, 1));
static_assert(euclid8(-7, -2, 4, 1));
static_assert(euclid8(7, 2, 3, 1));
static_assert(euclid8(0, -5, 0, 0));
static_assert(euclid8(-128, -1, -128, 0));
static_assert(euclid8(-128, 1, -128, 0));
static_assert(euclid8(-128, 127, -2, 126));
static_assert(euclid8(127, -128, 0, 127));
static_assert(euclid8(-1, -128, 1, 127));
static_assert(euclid8(-128, -128, 1, 0));
static_assert(euclid<Part::Quotient>(Words{}, w64(INT64_MIN), w64(-1)) == w64(INT64_MIN));
static_assert(euclid<Part::Remainder>(Words{}, w64(INT64_MIN), w64(-1)) == w64(0));
// On the runtime's smalls nothing wraps: the least small over -1 is 2^62.
static_assert(euclid<Part::Quotient>(Smalls{}, smallLeast, -1) == std::int64_t{1} << 62);
static_assert(euclid<Part::Remainder>(Smalls{}, smallLeast, -1) == 0);

// Euclid's definition for one dividend over every divisor but zero:
// a = q*b + r modulo 2^8, and 0 <= r < |b|, except at the least value over
// -1, where the quotient wraps and the remainder is 0.
constexpr bool euclidDefinition(std::int64_t a) {
  Words d;
  for (std::int64_t b = -128; b < 128; ++b) {
    if (b == 0)
      continue;
    Word q = div8<Part::Quotient>(a, b), r = div8<Part::Remainder>(a, b);
    if (!(d.add(Words::of(q.bits * w8(b).bits, 8), r) == w8(a)))
      return false;
    std::int64_t rem = Words::signedOf(r), magnitude = b < 0 ? -b : b;
    if (rem < 0 || rem >= magnitude)
      return false;
  }
  return true;
}

// Shifts, by hand.
template <Direction Dir, Signedness S>
constexpr Word sh8(std::int64_t a, std::int64_t amount) {
  return shift<Dir, S>(Words{}, w8(a), w8(amount));
}
static_assert(sh8<Direction::Left, Signedness::Signed>(1, 7) == w8(0x80));
static_assert(sh8<Direction::Left, Signedness::Unsigned>(1, 7) == w8(0x80));
static_assert(sh8<Direction::Left, Signedness::Signed>(1, 8) == w8(0));
static_assert(sh8<Direction::Left, Signedness::Unsigned>(1, 255) == w8(0));
static_assert(sh8<Direction::Left, Signedness::Signed>(4, -1) == w8(2));
static_assert(sh8<Direction::Left, Signedness::Unsigned>(4, 255) == w8(0));
static_assert(sh8<Direction::Left, Signedness::Signed>(-128, -1) == w8(-64));
static_assert(sh8<Direction::Left, Signedness::Signed>(1, -128) == w8(0));
static_assert(sh8<Direction::Left, Signedness::Signed>(-1, -128) == w8(-1));
static_assert(sh8<Direction::Right, Signedness::Signed>(-128, 7) == w8(-1));
static_assert(sh8<Direction::Right, Signedness::Signed>(-128, 8) == w8(-1));
static_assert(sh8<Direction::Right, Signedness::Unsigned>(0x80, 7) == w8(1));
static_assert(sh8<Direction::Right, Signedness::Unsigned>(0x80, 8) == w8(0));
static_assert(sh8<Direction::Right, Signedness::Signed>(4, -1) == w8(8));
static_assert(sh8<Direction::Right, Signedness::Unsigned>(4, 255) == w8(0));

// The shifts of one value by every amount below the width, against
// multiplication and division by powers of two.
constexpr bool shiftsAsArithmetic(std::uint64_t a) {
  for (unsigned k = 0; k < 8; ++k) {
    std::uint64_t p = std::uint64_t{1} << k;
    std::int64_t sa = Words::signedOf(w8(static_cast<std::int64_t>(a)));
    std::int64_t floor = sa >= 0 ? sa / static_cast<std::int64_t>(p)
                                 : -((-sa + static_cast<std::int64_t>(p) - 1) /
                                     static_cast<std::int64_t>(p));
    auto amount = static_cast<std::int64_t>(k), value = static_cast<std::int64_t>(a);
    if (!(sh8<Direction::Left, Signedness::Unsigned>(value, amount) ==
          Words::of(a * p, 8)) ||
        !(sh8<Direction::Left, Signedness::Signed>(value, amount) == Words::of(a * p, 8)) ||
        !(sh8<Direction::Right, Signedness::Unsigned>(value, amount) == Words::of(a / p, 8)) ||
        !(sh8<Direction::Right, Signedness::Signed>(value, amount) == w8(floor)))
      return false;
  }
  return true;
}

// Characters, by hand.
template <Signedness S>
constexpr Word chr(Word x) {
  return toChar<S>(Words{}, x);
}
static_assert(chr<Signedness::Signed>(w8(-1)) == w32(0));
static_assert(chr<Signedness::Unsigned>(w8(0xFF)) == w32(0xFF));
static_assert(chr<Signedness::Unsigned>(w32(0xD7FF)) == w32(0xD7FF));
static_assert(chr<Signedness::Unsigned>(w32(0xE000)) == w32(0xE000));
static_assert(chr<Signedness::Unsigned>(w32(0x10FFFF)) == w32(0x10FFFF));
static_assert(chr<Signedness::Unsigned>(w32(0xD800)) == w32(0));
static_assert(chr<Signedness::Unsigned>(w32(0xDFFF)) == w32(0));
static_assert(chr<Signedness::Unsigned>(w32(0x110000)) == w32(0));
static_assert(chr<Signedness::Unsigned>(w64((std::int64_t{1} << 32) + 65)) == w32(0));
static_assert(chr<Signedness::Signed>(w64(INT64_MIN)) == w32(0));
static_assert(chr<Signedness::Unsigned>(w32(0xFFFFFFFF)) == w32(0));
static_assert(chr<Signedness::Signed>(w32(0x41)) == w32(0x41));

// The guards' conditions, by hand.
static_assert(!nonzero(Words{}, w8(0)).holds);
static_assert(nonzero(Words{}, w8(-128)).holds);
static_assert(inBounds(Words{}, w64(0), w64(1)).holds);
static_assert(!inBounds(Words{}, w64(1), w64(1)).holds);
static_assert(!inBounds(Words{}, w64(-1), w64(5)).holds);
static_assert(inRange(Words{}, w64(0), w64(0), w64(0)).holds);
static_assert(inRange(Words{}, w64(2), w64(3), w64(5)).holds);
static_assert(!inRange(Words{}, w64(2), w64(4), w64(5)).holds);
static_assert(!inRange(Words{}, w64(-1), w64(1), w64(5)).holds);
static_assert(!inRange(Words{}, w64(1), w64(-1), w64(5)).holds);
static_assert(!inRange(Words{}, w64(6), w64(0), w64(5)).holds);
static_assert(!inRange(Words{}, w64(INT64_MAX), w64(INT64_MAX), w64(INT64_MAX)).holds);
static_assert(!inRange(Words{}, w64(0), w64(1), w64(-1)).holds);
static_assert(!nonempty(Words{}, w64(0)).holds);
static_assert(nonempty(Words{}, w64(1)).holds);

// A Double's finiteness on its bits: the constant is the bits of an
// infinity as C++'s own double has them, and the edges of each class.
constexpr Word bitsOf(double x) { return Words::of(std::bit_cast<std::uint64_t>(x), 64); }
static_assert(std::bit_cast<std::uint64_t>(std::numeric_limits<double>::infinity()) ==
              static_cast<std::uint64_t>(doubleInfinity));
static_assert(finite(Words{}, bitsOf(0.0)).holds);
static_assert(finite(Words{}, bitsOf(-0.0)).holds);
static_assert(finite(Words{}, bitsOf(std::numeric_limits<double>::max())).holds);
static_assert(finite(Words{}, bitsOf(-std::numeric_limits<double>::max())).holds);
static_assert(finite(Words{}, bitsOf(std::numeric_limits<double>::denorm_min())).holds);
static_assert(!finite(Words{}, bitsOf(std::numeric_limits<double>::infinity())).holds);
static_assert(!finite(Words{}, bitsOf(-std::numeric_limits<double>::infinity())).holds);
static_assert(!finite(Words{}, bitsOf(std::numeric_limits<double>::quiet_NaN())).holds);
static_assert(!finite(Words{}, w64(0x7FF0000000000001)).holds);

// One static_assert per input: each is one constant evaluation.
template <std::uint64_t A>
struct ForByte {
  static_assert(euclidDefinition(static_cast<std::int64_t>(A) - 128));
  static_assert(shiftsAsArithmetic(A));
};

template <Law L, std::uint64_t A>
struct ForLawInput {
  static_assert(LawAt<L>::holds(A));
};

template <std::uint64_t... A>
constexpr bool everyByte(std::integer_sequence<std::uint64_t, A...>) {
  return ((sizeof(ForByte<A>) > 0) && ...);
}

template <Law L, std::uint64_t... A>
constexpr bool everyInput(std::integer_sequence<std::uint64_t, A...>) {
  return ((sizeof(ForLawInput<L, A>) > 0) && ...);
}

// Every law the specification lists (allLaws, printed beside Law), so a law
// added without its statement in Laws.h does not build.
template <std::size_t... I>
constexpr bool everyLaw(std::index_sequence<I...>) {
  return (everyInput<allLaws[I]>(
              std::make_integer_sequence<std::uint64_t, LawAt<allLaws[I]>::inputs>()) &&
          ...);
}

static_assert(everyByte(std::make_integer_sequence<std::uint64_t, 256>()));
static_assert(everyLaw(std::make_index_sequence<sizeof(allLaws) / sizeof(allLaws[0])>()));

} // namespace idr::numeric::checks

#endif // IDR_IR_NUMERIC_CHECKS_H
