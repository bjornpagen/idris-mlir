// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A string from any bytes. Ill-formed input is replaced as the Unicode
// Standard recommends (chapter 3, U+FFFD substitution of maximal subparts).
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <simdutf.h>

namespace {

// The well-formed UTF-8 sequences longer than a byte, as the Unicode
// Standard tabulates them (chapter 3): the lead bytes of a row, the range
// of the byte after the lead, and the sequence's length. Every later byte
// is a continuation byte, 80..BF; the second byte's range is narrower after
// E0 and F0, which would otherwise begin overlong forms, ED, which would
// encode surrogates, and F4, which would pass U+10FFFF.
struct WellFormed {
  unsigned char firstLead, lastLead, low, high;
  size_t length;
};
constexpr WellFormed wellFormed[] = {
    {0xC2, 0xDF, 0x80, 0xBF, 2}, {0xE0, 0xE0, 0xA0, 0xBF, 3}, {0xE1, 0xEC, 0x80, 0xBF, 3},
    {0xED, 0xED, 0x80, 0x9F, 3}, {0xEE, 0xEF, 0x80, 0xBF, 3}, {0xF0, 0xF0, 0x90, 0xBF, 4},
    {0xF1, 0xF3, 0x80, 0xBF, 4}, {0xF4, 0xF4, 0x80, 0x8F, 4},
};

// The length of the maximal subpart at p, where n > 0 bytes start no
// well-formed sequence: the longest prefix of a well-formed sequence there,
// or 1 when no well-formed sequence starts with p[0].
size_t maximalSubpart(const char *p, size_t n) {
  auto lead = static_cast<unsigned char>(p[0]);
  for (const WellFormed &row : wellFormed) {
    if (lead < row.firstLead || lead > row.lastLead)
      continue;
    size_t length = 1;
    while (length < row.length && length < n) {
      auto next = static_cast<unsigned char>(p[length]);
      if (next < (length == 1 ? row.low : 0x80) || next > (length == 1 ? row.high : 0xBF))
        break;
      ++length;
    }
    return length;
  }
  return 1;
}

} // namespace

// Each maximal subpart becomes one U+FFFD, and decoding goes on after it. A
// truncated sequence is one replacement, and a byte that no well-formed
// sequence starts with, or that cannot follow what precedes it, is one of
// its own: an overlong C0 80 is two, an encoded surrogate ED A0 80 three.
//
// One pass. simdutf validates a run and counts its scalars together, and
// stops where an ill-formed sequence starts. The first run, which ends at
// an ill-formed sequence, is copied; then each step replaces the maximal
// subpart at `at`, at least one byte, and copies the valid run after it,
// so `at` grows every step and the loop ends at the input's end. The
// string's size is known only at the end, so the cell is made for the
// most it can take, the valid prefix and three bytes for every byte after
// it, and its lengths are set to what was written: the cell may be larger
// than its string, which freeing never reads. Well-formed input, nearly
// every input, is the first run whole and fills its cell exactly.
extern "C" const idris_rt_str *idris_rt_str_from_bytes(const char *p, size_t n) {
  if (n == 0)
    return &rt::strings::emptyString;
  const simdutf::implementation &utf8 = rt::strings::implementation();
  simdutf::utf8_result first = utf8.validate_utf8_with_counts(p, n);
  if (first.error == simdutf::SUCCESS) {
    idris_rt_str *s = rt::strings::newString(n, first.utf32_length());
    memcpy(rt::strings::mutableBytes(s), p, n);
    return s;
  }
  static constexpr char replacement[] = "\xEF\xBF\xBD";
  constexpr size_t replacementBytes = sizeof replacement - 1;
  size_t room;
  if (__builtin_mul_overflow(n - first.input_count, replacementBytes, &room) ||
      __builtin_add_overflow(room, first.input_count, &room))
    rt::alloc::outOfMemory();
  idris_rt_str *s = rt::strings::newString(room, 0);
  char *start = rt::strings::mutableBytes(s);
  memcpy(start, p, first.input_count);
  char *to = start + first.input_count;
  uint64_t scalars = first.utf32_length();
  const char *at = p + first.input_count;
  const char *end = p + n;
  while (at < end) {
    at += maximalSubpart(at, static_cast<size_t>(end - at));
    memcpy(to, replacement, replacementBytes);
    to += replacementBytes;
    ++scalars;
    if (at < end) {
      simdutf::utf8_result run = utf8.validate_utf8_with_counts(at, static_cast<size_t>(end - at));
      memcpy(to, at, run.input_count);
      to += run.input_count;
      scalars += run.utf32_length();
      at += run.input_count;
    }
  }
  s->bytes = static_cast<uint64_t>(to - start);
  s->scalars = scalars;
  return s;
}
