// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A string's cell, the empty string, and making strings.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Rc/Rc.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <simdutf.h>

namespace rt::strings {

idris_rt_str *newString(uint64_t bytes, uint64_t scalars) {
  auto *s =
      static_cast<idris_rt_str *>(rt::alloc::newCell(sizeof(idris_rt_str) + bytes, stringInfo));
  s->bytes = bytes;
  s->scalars = scalars;
  return s;
}

// One pass over the bytes: their scalar count, which says whether they are
// ASCII too.
const idris_rt_str *stringOf(const char *p, size_t n) {
  if (n == 0)
    return &emptyString;
  idris_rt_str *s = newString(n, implementation().count_utf8(p, n));
  memcpy(mutableBytes(s), p, n);
  return s;
}

const idris_rt_str *asciiOf(const char *p, size_t n) {
  if (n == 0)
    return &emptyString;
  idris_rt_str *s = newString(n, n);
  memcpy(mutableBytes(s), p, n);
  return s;
}

} // namespace rt::strings

extern "C" const idris_rt_str *idris_rt_str_from_utf8(const char *p, size_t n) {
  return rt::strings::stringOf(p, n);
}

extern "C" idris_rt_str *idris_rt_str_alloc(int64_t bytes, int64_t scalars) {
  if (bytes == 0)
    return const_cast<idris_rt_str *>(&rt::strings::emptyString);
  return rt::strings::newString(static_cast<uint64_t>(bytes), static_cast<uint64_t>(scalars));
}

extern "C" int64_t idris_rt_str_bytes_length(const idris_rt_str *s) {
  return static_cast<int64_t>(s->bytes);
}

extern "C" void idris_rt_str_release(const idris_rt_str *s) { rt::rc::decCell(s); }
