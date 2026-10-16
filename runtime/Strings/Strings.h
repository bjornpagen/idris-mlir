// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::strings: strings, UTF-8 bytes with their scalar count, over simdutf,
// and the text of integers and scalars. A string is one cell, header,
// lengths and bytes together, so freeing it is freeing the cell. What every
// string operation and the output path call per character or per digit is
// inline here.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "Rc/Rc.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace simdutf {
class implementation;
} // namespace simdutf

namespace rt::strings {

// A string's info word: its tag is 0, since its lengths say all there is.
inline constexpr uint32_t stringInfo = idris_rt_info(0, 0, IDRIS_RT_KIND_STRING);

// The one empty string, persistent: the result of every operation whose
// result is empty, never written.
inline constexpr idris_rt_str emptyString{{0, stringInfo}, 0, 0};

// Every byte ASCII. A scalar takes one byte exactly when it is ASCII, so the
// lengths say it, and say it of every string, a slice included.
inline bool isAscii(const idris_rt_str *s) { return s->bytes == s->scalars; }

// An argument returned as the result, which the caller owns: one more
// reference.
inline const idris_rt_str *shared(const idris_rt_str *s) {
  rt::rc::incCell(s);
  return s;
}

// Where a string's bytes go, after its lengths in the same cell.
inline char *mutableBytes(idris_rt_str *s) { return reinterpret_cast<char *>(s + 1); }

// A new string of `bytes` bytes that the caller fills, with its scalar count
// (Making.cpp).
idris_rt_str *newString(uint64_t bytes, uint64_t scalars);

// A string from bytes that are well-formed UTF-8.
const idris_rt_str *stringOf(const char *p, size_t n);

// A string from bytes that are all ASCII, as the text of a number is: its
// scalars are its bytes, so nothing counts them.
const idris_rt_str *asciiOf(const char *p, size_t n);

// Room for the decimal text of any 64-bit integer, sign included.
inline constexpr size_t intTextMax = 20;

// The decimal digits of an integer, written backwards from `end`; returns
// where they start.
[[gnu::always_inline]] inline char *formatUnsigned(uint64_t value, char *end) {
  do {
    *--end = static_cast<char>('0' + value % 10);
    value /= 10;
  } while (value != 0);
  return end;
}

inline char *formatSigned(int64_t value, char *end) {
  uint64_t magnitude = value < 0 ? 0 - static_cast<uint64_t>(value) : static_cast<uint64_t>(value);
  char *start = formatUnsigned(magnitude, end);
  if (value < 0)
    *--start = '-';
  return start;
}

// The number of bytes of c's UTF-8: 1 below 0x80, 2 below 0x800, 3 below
// 0x10000, else 4, of its bits read unsigned, so that every int32_t has
// one, the length encodeUtf8 writes it in.
inline size_t utf8Length(int32_t c) {
  auto u = static_cast<uint32_t>(c);
  return u < 0x80 ? 1 : u < 0x800 ? 2 : u < 0x10000 ? 3 : 4;
}

// The UTF-8 encoding of c into out, which has room for 4 bytes; returns its
// length. A one-byte encoding's lead byte has no prefix, so ASCII is
// written by the rule every length is.
inline size_t encodeUtf8(int32_t c, char *out) {
  auto u = static_cast<uint32_t>(c);
  size_t n = utf8Length(c);
  static constexpr uint32_t prefix[] = {0, 0, 0xC0, 0xE0, 0xF0};
  out[0] = static_cast<char>(prefix[n] | (u >> (6 * (n - 1))));
  for (size_t k = 1; k < n; ++k)
    out[k] = static_cast<char>(0x80 | ((u >> (6 * (n - 1 - k))) & 0x3F));
  return n;
}

// The simdutf implementation every string function calls (Simd.cpp).
const simdutf::implementation &implementation();

} // namespace rt::strings
