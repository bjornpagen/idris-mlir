// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Strings put together: two strings, a scalar before a string, and the
// parts generated code writes into a string it allocated.
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

// A character's UTF-8 written into a string being built
// (idris_rt_str_alloc), at an offset, giving the next offset.
extern "C" int64_t idris_rt_str_put_char(idris_rt_str *s, int64_t offset, int32_t c) {
  char *at = rt::strings::mutableBytes(s) + offset;
  return offset + static_cast<int64_t>(rt::strings::encodeUtf8(c, at));
}

// A string's bytes written into a string being built, at an offset, giving
// the next offset. An empty part copies nothing: both pointers are valid,
// its own bytes and the string's end, so the copy needs no test.
extern "C" int64_t idris_rt_str_put_str(idris_rt_str *s, int64_t offset, const idris_rt_str *part) {
  memcpy(rt::strings::mutableBytes(s) + offset, idris_rt_str_bytes(part), part->bytes);
  return offset + static_cast<int64_t>(part->bytes);
}

// The concatenation of two strings, a new string even where one is empty,
// since the result is fresh and never an argument; the empty one when both
// are.
extern "C" const idris_rt_str *idris_rt_str_append(const idris_rt_str *a, const idris_rt_str *b) {
  using namespace rt::strings;
  idris_rt_str *s = newString(a->bytes + b->bytes, a->scalars + b->scalars);
  memcpy(mutableBytes(s), idris_rt_str_bytes(a), a->bytes);
  memcpy(mutableBytes(s) + a->bytes, idris_rt_str_bytes(b), b->bytes);
  return s;
}

// A character before a string.
extern "C" const idris_rt_str *idris_rt_str_cons(int32_t c, const idris_rt_str *s) {
  using namespace rt::strings;
  char encoded[4];
  size_t n = encodeUtf8(c, encoded);
  idris_rt_str *result = newString(n + s->bytes, s->scalars + 1);
  memcpy(mutableBytes(result), encoded, n);
  memcpy(mutableBytes(result) + n, idris_rt_str_bytes(s), s->bytes);
  return result;
}

// The string of one character.
extern "C" const idris_rt_str *idris_rt_str_from_char(int32_t c) {
  return idris_rt_str_cons(c, &rt::strings::emptyString);
}
