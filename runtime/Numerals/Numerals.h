// rt::numerals: `cast` from String. Idris documents no syntax for it and its
// backends disagree, so the cast reads what Idris's own syntax writes: a
// literal of the target type, with an optional sign before it, as the whole
// string. Any other string is 0, as a cast is total.
// - Every number type reads an integer literal: decimal digits, or 0b, 0o,
//   0x or 0X and digits of that base, in groups that single underscores may
//   separate (1_000). An integer type takes its value modulo 2^N; Double
//   the nearest double, as fromInteger does.
// - Double also reads a decimal literal, digits, a point and digits, with an
//   optional exponent (e, a sign, digits), and digits with an exponent and
//   no point, which is how a double's text is written when it has one
//   significant digit (1e21): every text of a double reads back as it, as
//   IEEE 754 requires of the two conversions, correctly rounded to nearest,
//   ties to even. It reads inf, infinity and nan, in any case, as IEEE 754
//   spells the infinities and NaN.
// So 12.7 is 0 as an Int, being no literal of one, and .5, 5., 1E3 and
// surrounding spaces are no number at all. rt::big reads an Integer's value
// and rt::doubles a Double's.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace rt::numerals {

// What `cast` from String reads in a string: an integer literal, which
// every number type reads; a decimal literal, infinity or NaN, which Double
// reads too; or no number.
struct Numeral {
  enum Kind { None, Integer, Decimal, Infinity, NaN };
  Kind kind = None;
  bool negative = false;
  // An integer literal's base, and where its digits start.
  unsigned base = 10;
  size_t digits = 0;
  // Whether underscores separate its digits.
  bool grouped = false;

  // The integer literal's value, of the n bytes at p it was read from,
  // modulo 2^64.
  uint64_t wrapped(const char *p, size_t n) const;
};

// What the n bytes at p are, read whole (Reading.cpp).
Numeral readNumeral(const char *p, size_t n);

} // namespace rt::numerals
