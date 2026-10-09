// rt.strings:scalars: a string as its scalars: its length, a scalar at an
// index, slices, and the reverse; and by byte offset, as an iterator walks
// it.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

export module rt.strings:scalars;

import :making;

namespace {

bool isContinuation(char byte) { return (static_cast<unsigned char>(byte) & 0xC0) == 0x80; }

// The byte offset of scalar i of s, 0 <= i <= its scalar count.
uint64_t offsetOf(const idris_rt_str *s, uint64_t i) {
  if (rt::strings::isAscii(s))
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

// The boundary an offset stands for: clamped to [0, bytes], then moved back
// to the start of the scalar whose encoding holds it. Byte 0 starts a
// scalar, so the walk back stops there at the latest.
uint64_t boundary(const idris_rt_str *s, int64_t offset) {
  if (offset <= 0)
    return 0;
  auto at = static_cast<uint64_t>(offset);
  if (at >= s->bytes)
    return s->bytes;
  const char *p = idris_rt_str_bytes(s);
  while (isContinuation(p[at]))
    --at;
  return at;
}

// The scalars [from, to) of s, as a new string.
const idris_rt_str *slice(const idris_rt_str *s, uint64_t from, uint64_t to) {
  if (from == to)
    return &rt::strings::emptyString;
  uint64_t begin = offsetOf(s, from);
  uint64_t end = to == s->scalars ? s->bytes : offsetOf(s, to);
  idris_rt_str *result = rt::strings::newString(end - begin, to - from, rt::strings::isAscii(s));
  memcpy(rt::strings::mutableBytes(result), idris_rt_str_bytes(s) + begin, end - begin);
  return result;
}

} // namespace

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
    return &rt::strings::emptyString;
  uint64_t to = count > length - from ? length : from + count;
  return slice(s, from, to);
}

extern "C" const idris_rt_str *idris_rt_str_reverse(const idris_rt_str *s) {
  if (s->bytes == 0)
    return rt::strings::shared(s);
  idris_rt_str *result = rt::strings::newString(s->bytes, s->scalars, rt::strings::isAscii(s));
  const char *from = idris_rt_str_bytes(s);
  char *to = rt::strings::mutableBytes(result) + s->bytes;
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

extern "C" int32_t idris_rt_str_scalar_at(const idris_rt_str *s, int64_t offset) {
  uint64_t at = boundary(s, offset);
  return at == s->bytes ? 0 : decode(idris_rt_str_bytes(s) + at);
}

extern "C" int64_t idris_rt_str_scalar_end(const idris_rt_str *s, int64_t offset) {
  uint64_t at = boundary(s, offset);
  if (at == s->bytes)
    return static_cast<int64_t>(at);
  if (rt::strings::isAscii(s))
    return static_cast<int64_t>(at + 1);
  const char *p = idris_rt_str_bytes(s);
  ++at;
  while (at < s->bytes && isContinuation(p[at]))
    ++at;
  return static_cast<int64_t>(at);
}

// A new string of the bytes from the boundary on keeps the flag of `s`, as
// a slice does: an ASCII flag stays true of every part of an ASCII string.
extern "C" const idris_rt_str *idris_rt_str_drop_bytes(const idris_rt_str *s, int64_t offset) {
  uint64_t at = boundary(s, offset);
  if (at == 0)
    return rt::strings::shared(s);
  if (at == s->bytes)
    return &rt::strings::emptyString;
  uint64_t n = s->bytes - at;
  const char *p = idris_rt_str_bytes(s) + at;
  bool ascii = rt::strings::isAscii(s);
  idris_rt_str *result = rt::strings::newString(n, ascii ? n : idris_rt_utf8_count(p, n), ascii);
  memcpy(rt::strings::mutableBytes(result), p, n);
  return result;
}
