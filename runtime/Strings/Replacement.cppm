// rt.strings:replacement: a string from any bytes. Ill-formed input is
// replaced as the Unicode Standard recommends (chapter 3, U+FFFD
// substitution of maximal subparts).
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <simdutf.h>

export module rt.strings:replacement;

import :making;
import :simd;

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

// The n bytes at p as runs of well-formed UTF-8, which simdutf finds, and
// the maximal subparts between them: run(q, k) for each run of k bytes at q,
// some of them empty, and bad() for each maximal subpart.
template <typename Run, typename Bad> void scan(const char *p, size_t n, Run run, Bad bad) {
  while (n > 0) {
    simdutf::result checked = rt::strings::implementation().validate_utf8_with_errors(p, n);
    size_t good = checked.error == simdutf::SUCCESS ? n : checked.count;
    run(p, good);
    p += good;
    n -= good;
    if (n > 0) {
      size_t skipped = maximalSubpart(p, n);
      bad();
      p += skipped;
      n -= skipped;
    }
  }
}

} // namespace

// Each maximal subpart becomes one U+FFFD, and decoding goes on after it. A
// truncated sequence is one replacement, and a byte that no well-formed
// sequence starts with, or that cannot follow what precedes it, is one of
// its own: an overlong C0 80 is two, an encoded surrogate ED A0 80 three.
// Two passes: the first sizes the string, the second writes it.
extern "C" const idris_rt_str *idris_rt_str_from_bytes(const char *p, size_t n) {
  if (rt::strings::implementation().validate_utf8(p, n))
    return rt::strings::stringOf(p, n);
  static constexpr char replacement[] = "\xEF\xBF\xBD";
  constexpr size_t replacementBytes = sizeof replacement - 1;
  uint64_t bytes = 0;
  uint64_t scalars = 0;
  scan(
      p, n,
      [&](const char *run, size_t k) {
        bytes += k;
        scalars += rt::strings::implementation().count_utf8(run, k);
      },
      [&] {
        bytes += replacementBytes;
        ++scalars;
      });
  idris_rt_str *s = rt::strings::newString(bytes, scalars, false);
  char *to = rt::strings::mutableBytes(s);
  scan(
      p, n,
      [&](const char *run, size_t k) {
        memcpy(to, run, k);
        to += k;
      },
      [&] {
        memcpy(to, replacement, replacementBytes);
        to += replacementBytes;
      });
  return s;
}
