// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::strings: strings, UTF-8 bytes with their scalar count and an ASCII
// flag, over simdutf, and the text of integers and scalars. A string is one
// cell, header, lengths and bytes together, so freeing it is freeing the
// cell.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace simdutf {
class implementation;
} // namespace simdutf

namespace rt::strings {

// The ASCII flag is the tag.
constexpr uint32_t stringInfo(bool ascii) { return idris_rt_info(ascii ? 1u : 0u, 0, IDRIS_RT_KIND_STRING); }

// The one empty string, persistent: the result of every operation whose
// result is empty, never written.
inline constexpr idris_rt_str emptyString{{0, stringInfo(true)}, 0, 0};

inline bool isAscii(const idris_rt_str *s) { return (s->header.info & 1) != 0; }

// An argument returned as the result, which the caller owns: one more
// reference.
inline const idris_rt_str *shared(const idris_rt_str *s) {
  idris_rt_inc(const_cast<idris_rt_str *>(s));
  return s;
}

// Where a string's bytes go, after its lengths in the same cell.
inline char *mutableBytes(idris_rt_str *s) { return reinterpret_cast<char *>(s + 1); }

// A new string of `bytes` bytes that the caller fills, with its scalar count
// and ASCII flag (Making.cpp).
idris_rt_str *newString(uint64_t bytes, uint64_t scalars, bool ascii);

// A string from bytes that are well-formed UTF-8.
const idris_rt_str *stringOf(const char *p, size_t n);

// Room for the decimal text of any 64-bit integer, sign included.
inline constexpr size_t intTextMax = 20;

// The decimal digits of an integer, written backwards from `end`; returns
// where they start (Integers.cpp).
char *formatUnsigned(uint64_t value, char *end);
char *formatSigned(int64_t value, char *end);

// The UTF-8 encoding of c into out, which has room for 4 bytes; returns its
// length (Utf8.cpp).
size_t encodeUtf8(int32_t c, char *out);

// The simdutf implementation every string function calls (Simd.cpp).
const simdutf::implementation &implementation();

} // namespace rt::strings
