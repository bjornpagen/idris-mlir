// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// UTF-8 as the Unicode Standard defines it (chapter 3), the model
// runtime-utf8 and runtime-strings hold the runtime's strings to. It is
// written from the Standard's text, not from the runtime: the decoder reads
// one byte at a time and never looks ahead, where the runtime validates runs
// with simdutf and measures each maximal subpart by scanning forward.
#pragma once
#include <stddef.h>
#include <stdint.h>

// Both functions are inline: the header is included by two programs.
namespace utf8model {
// The n bytes at p as the Unicode Standard decodes them, one byte at a
// time with no lookahead: a well-formed sequence (Table 3-7) is its scalar;
// a byte that does not fit the sequence it continues ends that sequence
// with one U+FFFD and is read again as a start; a byte no sequence starts
// with is one U+FFFD; the end of input inside a sequence is one U+FFFD.
// Writes at most n scalars to out; returns their count.
size_t decode(const unsigned char *p, size_t n, uint32_t *out);
// The UTF-8 of a scalar value into out (room for 4); returns its length.
size_t encode(uint32_t scalar, unsigned char *out);
}

namespace utf8model {

// U+FFFD REPLACEMENT CHARACTER.
inline constexpr uint32_t replacement = 0xFFFD;

// The bytes one place of a well-formed sequence may hold, low to high.
struct Range {
  unsigned char low, high;
  constexpr bool holds(unsigned char byte) const { return low <= byte && byte <= high; }
};

// A row of Table 3-7, Well-Formed UTF-8 Byte Sequences: the code points it
// encodes, first to last, and the range of each of its `length` bytes.
struct Row {
  uint32_t first, last;
  size_t length;
  Range bytes[4];
};

// Table 3-7 as the Standard writes it. A sequence is well-formed exactly
// when it is some row's bytes, each in its range, and the first ranges of
// two rows never meet, so a sequence's first byte names its row. The
// programs draw scalars and byte strings from it too, so what they test is
// what the decoder reads.
inline constexpr Row table37[] = {
    {0x0000, 0x007F, 1, {{0x00, 0x7F}}},
    {0x0080, 0x07FF, 2, {{0xC2, 0xDF}, {0x80, 0xBF}}},
    {0x0800, 0x0FFF, 3, {{0xE0, 0xE0}, {0xA0, 0xBF}, {0x80, 0xBF}}},
    {0x1000, 0xCFFF, 3, {{0xE1, 0xEC}, {0x80, 0xBF}, {0x80, 0xBF}}},
    {0xD000, 0xD7FF, 3, {{0xED, 0xED}, {0x80, 0x9F}, {0x80, 0xBF}}},
    {0xE000, 0xFFFF, 3, {{0xEE, 0xEF}, {0x80, 0xBF}, {0x80, 0xBF}}},
    {0x10000, 0x3FFFF, 4, {{0xF0, 0xF0}, {0x90, 0xBF}, {0x80, 0xBF}, {0x80, 0xBF}}},
    {0x40000, 0xFFFFF, 4, {{0xF1, 0xF3}, {0x80, 0xBF}, {0x80, 0xBF}, {0x80, 0xBF}}},
    {0x100000, 0x10FFFF, 4, {{0xF4, 0xF4}, {0x80, 0x8F}, {0x80, 0xBF}, {0x80, 0xBF}}},
};
inline constexpr size_t rows = sizeof table37 / sizeof table37[0];

// The row whose first range holds `lead`, or `rows` when none does: the
// Standard's bytes no sequence starts with (80..C1, F5..FF).
inline size_t rowStartedBy(unsigned char lead) {
  size_t row = 0;
  while (row < rows && !table37[row].bytes[0].holds(lead))
    ++row;
  return row;
}

inline size_t decode(const unsigned char *p, size_t n, uint32_t *out) {
  size_t count = 0;
  // The sequence being read: its row, how many of its bytes are read (0
  // between sequences) and its scalar's bits so far. A sequence ends in
  // exactly one output, its scalar or one U+FFFD, and a byte no sequence
  // starts with is one, so there are at most n.
  size_t row = 0;
  size_t read = 0;
  uint32_t scalar = 0;
  for (size_t i = 0; i < n; ++i) {
    unsigned char byte = p[i];
    if (read > 0 && !table37[row].bytes[read].holds(byte)) {
      out[count++] = replacement;
      read = 0;
    }
    if (read == 0) {
      row = rowStartedBy(byte);
      // The Standard's two kinds of maximal subpart: a prefix of a
      // well-formed sequence (above, and at the end of input), or this one
      // byte, which no well-formed sequence starts with.
      if (row == rows) {
        out[count++] = replacement;
        continue;
      }
      // The first byte of a sequence of L bytes is L ones (none when L is
      // 1), a zero, then the scalar's bits: 0x7F >> (L - 1) keeps the zero
      // and those bits.
      scalar = byte & (0x7Fu >> (table37[row].length - 1));
    } else {
      scalar = scalar << 6 | (byte & 0x3Fu);
    }
    if (++read == table37[row].length) {
      out[count++] = scalar;
      read = 0;
    }
  }
  if (read > 0)
    out[count++] = replacement;
  return count;
}

inline size_t encode(uint32_t scalar, unsigned char *out) {
  // Table 3-6, UTF-8 Bit Distribution: up to 7 bits in one byte, 11 in
  // two, 16 in three, 21 in four. The first byte is the length's marker
  // and the high bits; each later byte is 10 and six bits.
  size_t length = scalar < 0x80 ? 1 : scalar < 0x800 ? 2 : scalar < 0x10000 ? 3 : 4;
  constexpr unsigned char marker[] = {0x00, 0xC0, 0xE0, 0xF0};
  out[0] = static_cast<unsigned char>(marker[length - 1] | scalar >> 6 * (length - 1));
  for (size_t k = 1; k < length; ++k)
    out[k] = static_cast<unsigned char>(0x80 | (scalar >> 6 * (length - 1 - k) & 0x3F));
  return length;
}

} // namespace utf8model
