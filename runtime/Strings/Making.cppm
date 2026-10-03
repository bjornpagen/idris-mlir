// rt.strings:making: a string's cell, the empty string, and making strings.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

export module rt.strings:making;

import rt.alloc;

namespace rt::strings {

// The ASCII flag is the tag.
constexpr uint32_t stringInfo(bool ascii) { return idris_rt_info(ascii ? 1u : 0u, 0, IDRIS_RT_KIND_STRING); }

inline constexpr idris_rt_str emptyString{{0, stringInfo(true)}, 0, 0};

bool isAscii(const idris_rt_str *s) { return (s->header.info & 1) != 0; }

// An argument returned as the result, which the caller owns: one more
// reference.
const idris_rt_str *shared(const idris_rt_str *s) {
  idris_rt_inc(const_cast<idris_rt_str *>(s));
  return s;
}

} // namespace rt::strings

export namespace rt::strings {

// A new string of `bytes` bytes that the caller fills, with its scalar count
// and ASCII flag, and where its bytes go.
idris_rt_str *newString(uint64_t bytes, uint64_t scalars, bool ascii) {
  auto *s = static_cast<idris_rt_str *>(
      rt::alloc::newCell(sizeof(idris_rt_str) + bytes, stringInfo(ascii)));
  s->bytes = bytes;
  s->scalars = scalars;
  return s;
}

char *mutableBytes(idris_rt_str *s) { return reinterpret_cast<char *>(s + 1); }

// A string from bytes that are well-formed UTF-8.
const idris_rt_str *stringOf(const char *p, size_t n) {
  if (n == 0)
    return &emptyString;
  idris_rt_str *s = newString(n, idris_rt_utf8_count(p, n), idris_rt_ascii(p, n));
  memcpy(mutableBytes(s), p, n);
  return s;
}

} // namespace rt::strings

extern "C" const char *idris_rt_str_bytes(const idris_rt_str *s) {
  return reinterpret_cast<const char *>(s + 1);
}

extern "C" const idris_rt_str *idris_rt_str_from_utf8(const char *p, size_t n) {
  return rt::strings::stringOf(p, n);
}

extern "C" idris_rt_str *idris_rt_str_alloc(int64_t bytes, int64_t scalars, int32_t ascii) {
  if (bytes == 0)
    return const_cast<idris_rt_str *>(&rt::strings::emptyString);
  return rt::strings::newString(static_cast<uint64_t>(bytes), static_cast<uint64_t>(scalars),
                                ascii != 0);
}

extern "C" int64_t idris_rt_str_bytes_length(const idris_rt_str *s) {
  return static_cast<int64_t>(s->bytes);
}

extern "C" int32_t idris_rt_str_is_ascii(const idris_rt_str *s) {
  return rt::strings::isAscii(s) ? 1 : 0;
}

extern "C" void idris_rt_str_release(const idris_rt_str *s) {
  idris_rt_dec(const_cast<idris_rt_str *>(s));
}
