// Strings: UTF-8 bytes with
// their scalar count and an ASCII flag, over simdutf. A string is one cell,
// header, lengths and bytes together, so freeing it is freeing the cell.
// PIN(runtime-quarantine), PIN(simdutf-dispatch) — see PINS.md

#include "internal.h"

#include <atomic>

#include <simdutf.h>
#include <string.h>

namespace {

// simdutf's own dispatch reads SIMDUTF_FORCE_IMPLEMENTATION on first use, and
// a value that names no implementation makes every later call fail, so a
// program's results would depend on its environment. The runtime picks the
// best implementation the CPU supports itself. The pointer starts null with
// no constructor, and racing threads store the same value.
std::atomic<const simdutf::implementation *> selected{nullptr};

const simdutf::implementation &implementation() {
  const simdutf::implementation *chosen = selected.load(std::memory_order_relaxed);
  if (chosen == nullptr) [[unlikely]] {
    chosen = simdutf::get_available_implementations().detect_best_supported();
    selected.store(chosen, std::memory_order_relaxed);
  }
  return *chosen;
}

// The ASCII flag is the tag.
constexpr uint32_t stringInfo(bool ascii) { return idris_rt_info(ascii ? 1u : 0u, 0, IDRIS_RT_KIND_STRING); }

constexpr idris_rt_str emptyString{{0, stringInfo(true)}, 0, 0};

bool isAscii(const idris_rt_str *s) { return (s->header.info & 1) != 0; }

// An argument returned as the result, which the caller owns: one more
// reference.
const idris_rt_str *shared(const idris_rt_str *s) {
  idris_rt_inc(const_cast<idris_rt_str *>(s));
  return s;
}

bool isContinuation(char byte) { return (static_cast<unsigned char>(byte) & 0xC0) == 0x80; }

// The byte offset of scalar i of s, 0 <= i <= its scalar count.
uint64_t offsetOf(const idris_rt_str *s, uint64_t i) {
  if (isAscii(s))
    return i;
  const char *p = idris_rt_str_bytes(s);
  uint64_t at = 0;
  for (uint64_t seen = 0; seen < i; ++seen) {
    ++at;
    while (at < s->bytes && isContinuation(p[at]))
      ++at;
  }
  return at;
}

// The scalar of well-formed UTF-8 at p.
int32_t decode(const char *p) {
  auto b0 = static_cast<unsigned char>(p[0]);
  if (b0 < 0x80)
    return b0;
  size_t n = b0 >= 0xF0 ? 4 : b0 >= 0xE0 ? 3 : 2;
  static constexpr unsigned char lead[] = {0, 0, 0x1F, 0x0F, 0x07};
  int32_t value = b0 & lead[n];
  for (size_t k = 1; k < n; ++k)
    value = (value << 6) | (static_cast<unsigned char>(p[k]) & 0x3F);
  return value;
}

// The scalars [from, to) of s, as a new string.
const idris_rt_str *slice(const idris_rt_str *s, uint64_t from, uint64_t to) {
  if (from == to)
    return &emptyString;
  uint64_t begin = offsetOf(s, from);
  uint64_t end = to == s->scalars ? s->bytes : offsetOf(s, to);
  idris_rt_str *result = rt::newString(end - begin, to - from, isAscii(s));
  memcpy(rt::mutableBytes(result), idris_rt_str_bytes(s) + begin, end - begin);
  return result;
}

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
    simdutf::result checked = implementation().validate_utf8_with_errors(p, n);
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

idris_rt_str *rt::newString(uint64_t bytes, uint64_t scalars, bool ascii) {
  auto *s =
      static_cast<idris_rt_str *>(rt::newCell(sizeof(idris_rt_str) + bytes, stringInfo(ascii)));
  s->bytes = bytes;
  s->scalars = scalars;
  return s;
}

char *rt::mutableBytes(idris_rt_str *s) { return reinterpret_cast<char *>(s + 1); }

const idris_rt_str *rt::stringOf(const char *p, size_t n) {
  if (n == 0)
    return &emptyString;
  idris_rt_str *s = newString(n, idris_rt_utf8_count(p, n), idris_rt_ascii(p, n));
  memcpy(mutableBytes(s), p, n);
  return s;
}

extern "C" size_t idris_rt_utf8_count(const char *p, size_t n) {
  return implementation().count_utf8(p, n);
}

extern "C" bool idris_rt_ascii(const char *p, size_t n) {
  return implementation().validate_ascii(p, n);
}

extern "C" const char *idris_rt_str_bytes(const idris_rt_str *s) {
  return reinterpret_cast<const char *>(s + 1);
}

extern "C" const idris_rt_str *idris_rt_str_from_utf8(const char *p, size_t n) {
  return rt::stringOf(p, n);
}

// Ill-formed input is replaced as the Unicode Standard recommends (chapter
// 3, U+FFFD substitution of maximal subparts): each maximal subpart becomes
// one U+FFFD, and decoding goes on after it. A truncated sequence is one
// replacement, and a byte that no well-formed sequence starts with, or that
// cannot follow what precedes it, is one of its own: an overlong C0 80 is
// two, an encoded surrogate ED A0 80 three. Two passes: the first sizes the
// string, the second writes it.
extern "C" const idris_rt_str *idris_rt_str_from_bytes(const char *p, size_t n) {
  if (implementation().validate_utf8(p, n))
    return rt::stringOf(p, n);
  static constexpr char replacement[] = "\xEF\xBF\xBD";
  constexpr size_t replacementBytes = sizeof replacement - 1;
  uint64_t bytes = 0;
  uint64_t scalars = 0;
  scan(
      p, n,
      [&](const char *run, size_t k) {
        bytes += k;
        scalars += implementation().count_utf8(run, k);
      },
      [&] {
        bytes += replacementBytes;
        ++scalars;
      });
  idris_rt_str *s = rt::newString(bytes, scalars, false);
  char *to = rt::mutableBytes(s);
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

extern "C" idris_rt_str *idris_rt_str_alloc(int64_t bytes, int64_t scalars, int32_t ascii) {
  if (bytes == 0)
    return const_cast<idris_rt_str *>(&emptyString);
  return rt::newString(static_cast<uint64_t>(bytes), static_cast<uint64_t>(scalars), ascii != 0);
}

extern "C" int64_t idris_rt_str_put_char(idris_rt_str *s, int64_t offset, int32_t c) {
  return offset + static_cast<int64_t>(rt::encodeUtf8(c, rt::mutableBytes(s) + offset));
}

extern "C" int64_t idris_rt_str_put_str(idris_rt_str *s, int64_t offset, const idris_rt_str *part) {
  if (part->bytes != 0)
    memcpy(rt::mutableBytes(s) + offset, idris_rt_str_bytes(part), part->bytes);
  return offset + static_cast<int64_t>(part->bytes);
}

extern "C" int64_t idris_rt_str_bytes_length(const idris_rt_str *s) {
  return static_cast<int64_t>(s->bytes);
}

extern "C" int32_t idris_rt_str_is_ascii(const idris_rt_str *s) { return isAscii(s) ? 1 : 0; }

extern "C" const idris_rt_str *idris_rt_str_append(const idris_rt_str *a, const idris_rt_str *b) {
  if (a->bytes == 0)
    return shared(b);
  if (b->bytes == 0)
    return shared(a);
  idris_rt_str *s =
      rt::newString(a->bytes + b->bytes, a->scalars + b->scalars, isAscii(a) && isAscii(b));
  memcpy(rt::mutableBytes(s), idris_rt_str_bytes(a), a->bytes);
  memcpy(rt::mutableBytes(s) + a->bytes, idris_rt_str_bytes(b), b->bytes);
  return s;
}

extern "C" const idris_rt_str *idris_rt_str_cons(int32_t c, const idris_rt_str *s) {
  char encoded[4];
  size_t n = rt::encodeUtf8(c, encoded);
  idris_rt_str *result = rt::newString(n + s->bytes, s->scalars + 1, n == 1 && isAscii(s));
  memcpy(rt::mutableBytes(result), encoded, n);
  memcpy(rt::mutableBytes(result) + n, idris_rt_str_bytes(s), s->bytes);
  return result;
}

extern "C" const idris_rt_str *idris_rt_str_from_char(int32_t c) {
  return idris_rt_str_cons(c, &emptyString);
}

extern "C" const idris_rt_str *idris_rt_str_show_s(int64_t value) {
  char text[rt::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::formatSigned(value, end);
  return rt::stringOf(start, static_cast<size_t>(end - start));
}

extern "C" const idris_rt_str *idris_rt_str_show_u(uint64_t value) {
  char text[rt::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::formatUnsigned(value, end);
  return rt::stringOf(start, static_cast<size_t>(end - start));
}

extern "C" const idris_rt_str *idris_rt_str_show_f64(double value) {
  char text[rt::doubleTextMax];
  size_t n = rt::formatDouble(value, text);
  return rt::stringOf(text, n);
}

extern "C" int64_t idris_rt_str_length(const idris_rt_str *s) {
  return static_cast<int64_t>(s->scalars);
}

extern "C" int32_t idris_rt_str_index(const idris_rt_str *s, int64_t i) {
  return decode(idris_rt_str_bytes(s) + offsetOf(s, static_cast<uint64_t>(i)));
}

extern "C" int32_t idris_rt_str_head(const idris_rt_str *s) {
  return decode(idris_rt_str_bytes(s));
}

extern "C" const idris_rt_str *idris_rt_str_tail(const idris_rt_str *s) {
  return slice(s, 1, s->scalars);
}

extern "C" const idris_rt_str *idris_rt_str_substr(const idris_rt_str *s, int64_t start,
                                                   int64_t len) {
  uint64_t length = s->scalars;
  uint64_t from = start > 0 ? static_cast<uint64_t>(start) : 0;
  uint64_t count = len > 0 ? static_cast<uint64_t>(len) : 0;
  if (from > length)
    return &emptyString;
  uint64_t to = count > length - from ? length : from + count;
  return slice(s, from, to);
}

extern "C" const idris_rt_str *idris_rt_str_reverse(const idris_rt_str *s) {
  if (s->bytes == 0)
    return shared(s);
  idris_rt_str *result = rt::newString(s->bytes, s->scalars, isAscii(s));
  const char *from = idris_rt_str_bytes(s);
  char *to = rt::mutableBytes(result) + s->bytes;
  uint64_t at = 0;
  while (at < s->bytes) {
    uint64_t next = at + 1;
    while (next < s->bytes && isContinuation(from[next]))
      ++next;
    to -= next - at;
    memcpy(to, from + at, next - at);
    at = next;
  }
  return result;
}

// UTF-8's byte order is the order of the scalar values it encodes.
extern "C" int32_t idris_rt_str_cmp(const idris_rt_str *a, const idris_rt_str *b) {
  const char *p = idris_rt_str_bytes(a);
  const char *q = idris_rt_str_bytes(b);
  uint64_t n = a->bytes < b->bytes ? a->bytes : b->bytes;
  for (uint64_t i = 0; i < n; ++i) {
    auto x = static_cast<unsigned char>(p[i]);
    auto y = static_cast<unsigned char>(q[i]);
    if (x != y)
      return x < y ? -1 : 1;
  }
  return a->bytes < b->bytes ? -1 : a->bytes > b->bytes ? 1 : 0;
}

extern "C" void idris_rt_str_release(const idris_rt_str *s) {
  idris_rt_dec(const_cast<idris_rt_str *>(s));
}
