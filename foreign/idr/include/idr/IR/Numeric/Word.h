// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Fixed-width words, the domain the inline ops fold over and the meanings'
// edge cases are checked in when the compiler is built: a word is its bits
// and its width, and every operation is exact on the width's bits, as an
// arith op on that integer type is. All of it is constexpr, so a
// static_assert evaluates a meaning on words (Checks.h), which an APInt,
// not constexpr, could not.
//
// Freestanding, as Domain.h.
#ifndef IDR_IR_NUMERIC_WORD_H
#define IDR_IR_NUMERIC_WORD_H

#include "idr/IR/Numeric/Domain.h"

#include <cstdint>

namespace idr::numeric {

// A word of `width` bits, 1 to 64: `bits` holds it zero-extended, and
// nothing above the width is ever set.
struct Word {
  std::uint64_t bits;
  unsigned width;
  friend constexpr bool operator==(Word, Word) = default;
};

// A truth of words, which a meaning combines and selects on but cannot
// branch on: no conversion to bool exists. Who holds the final answer (a
// guard's folder) reads `holds` by name.
struct Bit {
  bool holds;
};

struct Words {
  using Value = Word;
  using Truth = Bit;
  static constexpr Overflow overflow = Overflow::Wraps;

  // The bits of a width set.
  static constexpr std::uint64_t mask(unsigned width) {
    return width >= 64 ? ~std::uint64_t{0} : (std::uint64_t{1} << width) - 1;
  }
  // The word read signed: its top bit the sign.
  static constexpr std::int64_t signedOf(Word a) {
    std::uint64_t sign = std::uint64_t{1} << (a.width - 1);
    return static_cast<std::int64_t>((a.bits ^ sign) - sign);
  }
  static constexpr Word of(std::uint64_t bits, unsigned width) {
    return {bits & mask(width), width};
  }

  constexpr unsigned width(Word a) const { return a.width; }
  constexpr Word constant(std::int64_t c, Word like) const {
    return of(static_cast<std::uint64_t>(c), like.width);
  }
  constexpr Word least(Word like) const {
    return {std::uint64_t{1} << (like.width - 1), like.width};
  }

  constexpr Word add(Word a, Word b) const { return of(a.bits + b.bits, a.width); }
  constexpr Word sub(Word a, Word b) const { return of(a.bits - b.bits, a.width); }
  constexpr Word bitAnd(Word a, Word b) const { return {a.bits & b.bits, a.width}; }

  // The divisor is safe: never -1 under the least value, so the signed
  // quotient of the sign-extended words is exact in 64 bits, and so is the
  // remainder.
  constexpr Word quotientTowardZero(Word a, const SafeDivisor<Words> &s) const {
    return of(static_cast<std::uint64_t>(signedOf(a) / signedOf(s.value())), a.width);
  }
  constexpr Word remainderTowardZero(Word a, const SafeDivisor<Words> &s) const {
    return of(static_cast<std::uint64_t>(signedOf(a) % signedOf(s.value())), a.width);
  }

  constexpr Word shiftLeft(Word a, const BelowWidth<Words> &n) const {
    return of(a.bits << n.value().bits, a.width);
  }
  // C++20 defines >> of a negative signed value as the arithmetic shift.
  constexpr Word shiftRightArithmetic(Word a, const BelowWidth<Words> &n) const {
    return of(static_cast<std::uint64_t>(signedOf(a) >> n.value().bits), a.width);
  }
  constexpr Word shiftRightLogical(Word a, const BelowWidth<Words> &n) const {
    return {a.bits >> n.value().bits, a.width};
  }

  // Widening to a width at least the word's, and narrowing to one at most
  // it; the same width is the word.
  constexpr Word extendSigned(Word a, unsigned width) const {
    return of(static_cast<std::uint64_t>(signedOf(a)), width);
  }
  constexpr Word extendUnsigned(Word a, unsigned width) const { return {a.bits, width}; }
  constexpr Word truncate(Word a, unsigned width) const { return of(a.bits, width); }

  constexpr Bit equal(Word a, Word b) const { return {a.bits == b.bits}; }
  constexpr Bit lessSigned(Word a, Word b) const { return {signedOf(a) < signedOf(b)}; }
  constexpr Bit lessUnsigned(Word a, Word b) const { return {a.bits < b.bits}; }
  constexpr Bit both(Bit t, Bit u) const { return {t.holds && u.holds}; }
  constexpr Bit either(Bit t, Bit u) const { return {t.holds || u.holds}; }
  constexpr Bit negation(Bit t) const { return {!t.holds}; }
  constexpr Word select(Bit t, Word a, Word b) const { return t.holds ? a : b; }
};

static_assert(Domain<Words>);

} // namespace idr::numeric

#endif // IDR_IR_NUMERIC_WORD_H
