// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The meaning of each op of inline arithmetic, written once over a numeric
// domain (Domain.h): Idris's Euclidean division of a signed integer, its
// total shifts, an integer as a Char, and the conditions of six guards. A
// meaning is a function of values; it never branches on a truth of its
// domain, only selects on it, so every domain computes the same function.
// The one choice made in C++ is a family constant (a signedness, a
// direction), a template parameter fixed when the op's class is generated.
//
// Each function is wrapped as a function object, `Euclid<Part>` and kin,
// which an op's generated trait names (InlineArith<F>, Trait.h): the
// specification says which meaning an op has, and nothing in C++ says it
// again.
//
// Freestanding, as Domain.h.
#ifndef IDR_IR_NUMERIC_INLINE_H
#define IDR_IR_NUMERIC_INLINE_H

#include "idr/IR/Numeric/Domain.h"

namespace idr::numeric {

//===----------------------------------------------------------------------===//
// Euclidean division
//===----------------------------------------------------------------------===//

// The Euclidean quotient or remainder of `a` by `b`, which is not zero: the
// remainder in [0, |b|), the quotient the one that leaves it. Truncating
// division's remainder takes the dividend's sign, so a negative one moves
// the quotient one step away from the divisor's sign. In a domain that
// wraps, the least value over -1 is the least value, remainder 0
// (`divisible`).
template <Part P, Arithmetic D>
constexpr typename D::Value euclid(const D &d, typename D::Value a, typename D::Value b) {
  auto zero = d.constant(0, a), one = d.constant(1, a);
  auto s = divisible(d, a, b);
  auto q = d.quotientTowardZero(a, s);
  auto r = d.remainderTowardZero(a, s);
  auto negative = d.lessSigned(r, zero);
  auto positiveDivisor = d.lessSigned(zero, s.value());
  if constexpr (P == Part::Quotient)
    return d.select(negative, d.select(positiveDivisor, d.sub(q, one), d.add(q, one)), q);
  else
    return d.select(negative,
                    d.select(positiveDivisor, d.add(r, s.value()), d.sub(r, s.value())), r);
}

//===----------------------------------------------------------------------===//
// Shifts
//===----------------------------------------------------------------------===//

// `a` moved left by `places`, read unsigned: from the width on, every bit
// is shifted out.
template <Domain D>
constexpr typename D::Value movedLeft(const D &d, typename D::Value a, typename D::Value places) {
  auto huge = d.negation(d.lessUnsigned(places, d.constant(d.width(a), places)));
  return d.select(huge, d.constant(0, a), d.shiftLeft(a, belowWidth(d, places)));
}

// `a` moved right by `places`, read unsigned, filling as `S` says: with
// the sign, which is all that is left from the width on, or with zeros.
template <Signedness S, Domain D>
constexpr typename D::Value movedRight(const D &d, typename D::Value a,
                                       typename D::Value places) {
  auto huge = d.negation(d.lessUnsigned(places, d.constant(d.width(a), places)));
  auto masked = belowWidth(d, places);
  if constexpr (S == Signedness::Signed) {
    auto fill = d.shiftRightArithmetic(a, belowWidth(d, d.constant(d.width(a) - 1, a)));
    return d.select(huge, fill, d.shiftRightArithmetic(a, masked));
  } else {
    return d.select(huge, d.constant(0, a), d.shiftRightLogical(a, masked));
  }
}

// Idris's shift of a fixed-width integer, defined for every amount: the
// value moved, then wrapped to its width. A signed amount that is negative
// turns the direction; its negation, at the least value, stays negative and
// reads unsigned as a count past every width, which leaves only the fill.
template <Direction Dir, Signedness S, Domain D>
constexpr typename D::Value shift(const D &d, typename D::Value a, typename D::Value amount) {
  if constexpr (S == Signedness::Signed) {
    auto zero = d.constant(0, amount);
    auto turned = d.lessSigned(amount, zero);
    auto places = d.select(turned, d.sub(zero, amount), amount);
    auto left = movedLeft(d, a, places);
    auto right = movedRight<S>(d, a, places);
    if constexpr (Dir == Direction::Left)
      return d.select(turned, right, left);
    else
      return d.select(turned, left, right);
  } else {
    if constexpr (Dir == Direction::Left)
      return movedLeft(d, a, amount);
    else
      return movedRight<S>(d, a, amount);
  }
}

//===----------------------------------------------------------------------===//
// Characters
//===----------------------------------------------------------------------===//

// The width a Char is held in, and the width an integer is read at before
// it is tested: every Idris integer fits it.
inline constexpr unsigned charWidth = 32;
inline constexpr unsigned wideWidth = 64;

// Whether `x`, read unsigned, is a Unicode scalar value: below the
// surrogates, or past them and at most the last code point. A negative
// signed integer read so is past every code point.
template <Domain D>
constexpr typename D::Truth isScalarValue(const D &d, typename D::Value x) {
  auto atMost = [&](std::int64_t bound) { return d.negation(d.lessUnsigned(d.constant(bound, x), x)); };
  auto atLeast = [&](std::int64_t bound) { return d.negation(d.lessUnsigned(x, d.constant(bound, x))); };
  return d.either(atMost(0xD7FF), d.both(atLeast(0xE000), atMost(0x10FFFF)));
}

// An integer as a Char: itself, if it is a scalar value read as `S` says,
// else 0. It is widened before the test, so no bits are cut first: 2^32 + 65
// is no character, not 'A'.
template <Signedness S, Domain D>
constexpr typename D::Value toChar(const D &d, typename D::Value x) {
  auto wide = [&] {
    if constexpr (S == Signedness::Signed)
      return d.extendSigned(x, wideWidth);
    else
      return d.extendUnsigned(x, wideWidth);
  }();
  auto narrow = d.truncate(wide, charWidth);
  return d.select(isScalarValue(d, wide), narrow, d.constant(0, narrow));
}

//===----------------------------------------------------------------------===//
// Guard conditions
//===----------------------------------------------------------------------===//

// A divisor is not zero.
template <Domain D>
constexpr typename D::Truth nonzero(const D &d, typename D::Value v) {
  return d.negation(d.equal(v, d.constant(0, v)));
}

// An index is at least 0 and below the length of what it indexes, a length
// being never negative: read unsigned, a negative index is past every
// length, so one comparison is both.
template <Domain D>
constexpr typename D::Truth inBounds(const D &d, typename D::Value index,
                                     typename D::Value length) {
  return d.lessUnsigned(index, length);
}

// The bytes [offset, offset + count) lie in `size` bytes: both at least 0,
// the offset at most the size, and the count at most what is left after
// it. What is left is computed only where the offset is within the size;
// where it is not, the difference wraps, and the conjunction is false by
// its other part.
template <Domain D>
constexpr typename D::Truth inRange(const D &d, typename D::Value offset, typename D::Value count,
                                    typename D::Value size) {
  auto zero = d.constant(0, offset);
  auto notNegative = d.both(d.negation(d.lessSigned(offset, zero)),
                            d.negation(d.lessSigned(count, zero)));
  auto within = d.both(d.negation(d.lessSigned(size, offset)),
                       d.negation(d.lessSigned(d.sub(size, offset), count)));
  return d.both(notNegative, within);
}

// A string is not empty: its length, the runtime's count of its
// characters, is not zero.
template <Domain D>
constexpr typename D::Truth nonempty(const D &d, typename D::Value length) {
  return nonzero(d, length);
}

// The bits of an infinity of Idris's Double, IEEE binary64: the exponent
// field all set, the fraction clear.
inline constexpr std::int64_t doubleInfinity = 0x7FF0000000000000;

// A Double, read as its 64 bits, is neither infinite nor NaN: its exponent
// field, all of an infinity's bits, is not all set. The test is over the
// bits so that it is integer arithmetic the domains share; LLVM reads
// exactly this test as the class test it is (llvm.is.fpclass), so nothing
// is lost by writing it so.
template <Domain D>
constexpr typename D::Truth finite(const D &d, typename D::Value bits) {
  auto exponent = d.constant(doubleInfinity, bits);
  return d.negation(d.equal(d.bitAnd(bits, exponent), exponent));
}

// The values of a byte, as the exit's function takes a status: a
// `uint8_t`, which is what a parent reads.
inline constexpr std::int64_t byteValues = std::int64_t{UINT8_MAX} + 1;

// A value fits a byte: at least 0 and below the byte's values. Read
// unsigned, a negative value is past every byte, so one comparison is both.
template <Domain D>
constexpr typename D::Truth fitsByte(const D &d, typename D::Value v) {
  return d.lessUnsigned(v, d.constant(byteValues, v));
}

//===----------------------------------------------------------------------===//
// The meanings as function objects
//===----------------------------------------------------------------------===//

// What an op's trait instantiates: `apply` over any domain, and the number
// of operands it takes. A meaning of values (`Value`) or a condition
// (`Truth`), which the guard ops' traits take.

template <Part P>
struct Euclid {
  static constexpr unsigned arity = 2;
  template <Arithmetic D>
  static constexpr typename D::Value apply(const D &d, typename D::Value a, typename D::Value b) {
    return euclid<P>(d, a, b);
  }
};

template <Direction Dir, Signedness S>
struct Shift {
  static constexpr unsigned arity = 2;
  template <Domain D>
  static constexpr typename D::Value apply(const D &d, typename D::Value a,
                                           typename D::Value amount) {
    return shift<Dir, S>(d, a, amount);
  }
};

template <Signedness S>
struct ToChar {
  static constexpr unsigned arity = 1;
  template <Domain D>
  static constexpr typename D::Value apply(const D &d, typename D::Value x) {
    return toChar<S>(d, x);
  }
};

// The meanings at the family constants, as the specification names them
// (Spec.Ops.Numeric's inlineName): an op's trait is InlineArith<one of
// these>.
using EuclidQuotient = Euclid<Part::Quotient>;
using EuclidRemainder = Euclid<Part::Remainder>;
using ShiftLeftSigned = Shift<Direction::Left, Signedness::Signed>;
using ShiftLeftUnsigned = Shift<Direction::Left, Signedness::Unsigned>;
using ShiftRightSigned = Shift<Direction::Right, Signedness::Signed>;
using ShiftRightUnsigned = Shift<Direction::Right, Signedness::Unsigned>;
using ToCharSigned = ToChar<Signedness::Signed>;
using ToCharUnsigned = ToChar<Signedness::Unsigned>;

struct Nonzero {
  static constexpr unsigned arity = 1;
  template <Domain D>
  static constexpr typename D::Truth apply(const D &d, typename D::Value v) {
    return nonzero(d, v);
  }
};

struct InBounds {
  static constexpr unsigned arity = 2;
  template <Domain D>
  static constexpr typename D::Truth apply(const D &d, typename D::Value index,
                                           typename D::Value length) {
    return inBounds(d, index, length);
  }
};

struct InRange {
  static constexpr unsigned arity = 3;
  template <Domain D>
  static constexpr typename D::Truth apply(const D &d, typename D::Value offset,
                                           typename D::Value count, typename D::Value size) {
    return inRange(d, offset, count, size);
  }
};

struct Nonempty {
  static constexpr unsigned arity = 1;
  template <Domain D>
  static constexpr typename D::Truth apply(const D &d, typename D::Value length) {
    return nonempty(d, length);
  }
};

struct Finite {
  static constexpr unsigned arity = 1;
  template <Domain D>
  static constexpr typename D::Truth apply(const D &d, typename D::Value bits) {
    return finite(d, bits);
  }
};

struct FitsByte {
  static constexpr unsigned arity = 1;
  template <Domain D>
  static constexpr typename D::Truth apply(const D &d, typename D::Value v) {
    return fitsByte(d, v);
  }
};

} // namespace idr::numeric

#endif // IDR_IR_NUMERIC_INLINE_H
