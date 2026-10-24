// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::numerals: `cast` from String, read once for every number type: what
// it reads in a string is readNumeral's (Reading.cpp). rt::big reads an
// Integer's value and rt::doubles a Double's.
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace rt::numerals {

// The sign a number is written with: Plus with none or `+`, Minus with `-`.
enum class Sign : unsigned char { Plus, Minus };

// What `cast` from String reads in a string: an integer literal, which
// every number type reads; a decimal literal, infinity or NaN, which Double
// reads too; or no number.
struct Numeral {
  enum Kind { None, Integer, Decimal, Infinity, NaN };
  Kind kind = None;
  Sign sign = Sign::Plus;
  // An integer literal's base, and where its digits start.
  unsigned base = 10;
  size_t digits = 0;
  // Whether underscores separate its digits.
  bool grouped = false;

  // The integer literal's value, of the n bytes at p it was read from,
  // modulo 2^64.
  uint64_t wrapped(const char *p, size_t n) const;

  // A magnitude with the numeral's sign: 0 - x under `-`, which wraps an
  // unsigned magnitude modulo 2^64 and makes no negative zero of a Double,
  // as an integer has none.
  template <class T>
  T withSign(T magnitude) const {
    return sign == Sign::Minus ? T{} - magnitude : magnitude;
  }
};

// What the n bytes at p are, read whole (Reading.cpp).
Numeral readNumeral(const char *p, size_t n);

} // namespace rt::numerals
