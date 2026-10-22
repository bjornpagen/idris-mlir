// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A string as its scalars: its length, a scalar at an index, slices, and
// the reverse; by byte offset, as an iterator walks it; and the iterator's
// step, the number of bytes of a scalar's UTF-8.
// PIN(runtime-quarantine) — see PINS.md
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace {

bool isContinuation(char byte) { return (static_cast<unsigned char>(byte) & 0xC0) == 0x80; }

// The byte offset `count` scalars on from the scalar that starts at byte
// `at` of s; the scalars it passes are within s. An ASCII string's scalars
// are its bytes.
uint64_t advance(const idris_rt_str *s, uint64_t at, uint64_t count) {
  if (rt::strings::isAscii(s))
    return at + count;
  const char *p = idris_rt_str_bytes(s);
  for (uint64_t seen = 0; seen < count; ++seen) {
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

// A string by byte offset, as the linear string iterator walks it: every
// offset has a meaning. The boundary an offset stands for: clamped to
// [0, bytes], then moved back to the start of the scalar whose encoding
// holds it. Byte 0 starts a scalar, so the walk back stops there at the
// latest.
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

// The scalars [from, to) of s, as a new string, or the empty one. The walk
// to its end starts where the walk to its start stopped.
const idris_rt_str *slice(const idris_rt_str *s, uint64_t from, uint64_t to) {
  uint64_t begin = advance(s, 0, from);
  uint64_t end = to == s->scalars ? s->bytes : advance(s, begin, to - from);
  idris_rt_str *result = rt::strings::newString(end - begin, to - from);
  memcpy(rt::strings::mutableBytes(result), idris_rt_str_bytes(s) + begin, end - begin);
  return result;
}

} // namespace

// The number of scalar values of a string.
extern "C" int64_t idris_rt_str_length(const idris_rt_str *s) {
  return static_cast<int64_t>(s->scalars);
}

// The scalar at an index, 0 <= index < length, which idr-lower checks first
// and crashes on.
extern "C" int32_t idris_rt_str_index(const idris_rt_str *s, int64_t i) {
  return decode(idris_rt_str_bytes(s) + advance(s, 0, static_cast<uint64_t>(i)));
}

// The first scalar of a string that is not empty, which idr-lower checks
// first and crashes on.
extern "C" int32_t idris_rt_str_head(const idris_rt_str *s) {
  return decode(idris_rt_str_bytes(s));
}

// The string without its first scalar, of a string that is not empty, which
// idr-lower checks first and crashes on.
extern "C" const idris_rt_str *idris_rt_str_tail(const idris_rt_str *s) {
  return slice(s, 1, s->scalars);
}

// The Prelude's substr: the scalars from `start`, at most `len` of them; ""
// when the start is past the end, and only those left when fewer than `len`
// are. A negative start or length, which only a call of the primitive
// itself passes, counts as 0. Clamped, the rule has no exception: the first
// scalar is the start clamped to [0, length], and the count `len` clamped
// to [0, length - first].
extern "C" const idris_rt_str *idris_rt_str_substr(const idris_rt_str *s, int64_t start,
                                                   int64_t len) {
  uint64_t length = s->scalars;
  uint64_t first = start > 0 ? static_cast<uint64_t>(start) : 0;
  uint64_t from = first < length ? first : length;
  uint64_t count = len > 0 ? static_cast<uint64_t>(len) : 0;
  uint64_t to = count > length - from ? length : from + count;
  return slice(s, from, to);
}

// The string's scalars in reverse order, a new string, never the argument;
// the empty one for the empty string.
extern "C" const idris_rt_str *idris_rt_str_reverse(const idris_rt_str *s) {
  idris_rt_str *result = rt::strings::newString(s->bytes, s->scalars);
  const char *from = idris_rt_str_bytes(s);
  char *to = rt::strings::mutableBytes(result) + s->bytes;
  // An ASCII string's scalars are its bytes, reversed by one loop the
  // compiler vectorizes; any other's are moved whole, a scalar at a time.
  if (rt::strings::isAscii(s)) {
    for (uint64_t i = 0; i < s->bytes; ++i)
      to[-1 - static_cast<int64_t>(i)] = from[i];
    return result;
  }
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

// The scalar that starts at the boundary an offset stands for; 0 at the end.
extern "C" int32_t idris_rt_str_scalar_at(const idris_rt_str *s, int64_t offset) {
  uint64_t at = boundary(s, offset);
  return at == s->bytes ? 0 : decode(idris_rt_str_bytes(s) + at);
}

// The iterator's step past the scalar it read: the number of bytes of a
// character's UTF-8, 1 to 4; for an int32_t that is no scalar value, the
// length its encoding as idris_rt_str_from_char writes it has.
extern "C" int64_t idris_rt_str_scalar_bytes(int32_t c) {
  return static_cast<int64_t>(rt::strings::utf8Length(c));
}

// The scalars from the boundary an offset stands for on: a new string of
// those bytes, from 0 too, since the result is fresh and never the
// argument; the persistent empty one at the end. An ASCII string's tail is
// ASCII; any other's scalars are its own less those of the bytes dropped,
// which an iterator's step keeps few.
extern "C" const idris_rt_str *idris_rt_str_drop_bytes(const idris_rt_str *s, int64_t offset) {
  uint64_t at = boundary(s, offset);
  uint64_t n = s->bytes - at;
  const char *bytes = idris_rt_str_bytes(s);
  idris_rt_str *result = rt::strings::newString(
      n, rt::strings::isAscii(s) ? n : s->scalars - idris_rt_utf8_count(bytes, at));
  memcpy(rt::strings::mutableBytes(result), bytes + at, n);
  return result;
}
