// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::numerals: `cast` from String, read once for every number type: what
// it reads in a string is readNumeral's (Reading.cpp). rt::big reads an
// Integer's value and rt::doubles a Double's.
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
