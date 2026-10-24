// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A string's cell, the empty string, and making strings.
#include "Alloc/Alloc.h"
#include "Strings/Simd.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace rt::strings {

// The empty string is the one empty string, so every string of no bytes is
// it. Its header is never written: what the caller writes after is no bytes.
idris_rt_str *newString(uint64_t bytes, uint64_t scalars) {
  if (bytes == 0)
    return const_cast<idris_rt_str *>(&emptyString);
  auto *s =
      static_cast<idris_rt_str *>(rt::alloc::newCell(sizeof(idris_rt_str) + bytes, stringInfo));
  s->bytes = bytes;
  s->scalars = scalars;
  return s;
}

// One pass over the bytes: their scalar count, which says whether they are
// ASCII too.
const idris_rt_str *stringOf(const char *p, size_t n) {
  idris_rt_str *s = newString(n, utf8.count_utf8(p, n));
  memcpy(mutableBytes(s), p, n);
  return s;
}

const idris_rt_str *asciiOf(const char *p, size_t n) {
  idris_rt_str *s = newString(n, n);
  memcpy(mutableBytes(s), p, n);
  return s;
}

} // namespace rt::strings

// The string of n bytes of well-formed UTF-8 at p: a new string, or the
// persistent empty one.
extern "C" const idris_rt_str *idris_rt_str_from_utf8(const char *p, size_t n) {
  return rt::strings::stringOf(p, n);
}

// A string built in place by idr.str.pack and idr.str.concat, which know
// its size from a first pass: a string of `bytes` bytes and `scalars`
// scalar values, whose bytes the caller then writes in order
// (idris_rt_str_put_char, idris_rt_str_put_str). For no bytes it is the
// persistent empty string, which a caller that writes no bytes never
// writes.
extern "C" idris_rt_str *idris_rt_str_alloc(int64_t bytes, int64_t scalars) {
  return rt::strings::newString(static_cast<uint64_t>(bytes), static_cast<uint64_t>(scalars));
}

// The number of bytes of a string.
extern "C" int64_t idris_rt_str_bytes_length(const idris_rt_str *s) {
  return static_cast<int64_t>(s->bytes);
}
