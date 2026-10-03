// rt.strings:concat: strings put together: two strings, a scalar before a
// string, and the parts generated code writes into a string it allocated.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

export module rt.strings:concat;

import :making;
import :utf8;

extern "C" int64_t idris_rt_str_put_char(idris_rt_str *s, int64_t offset, int32_t c) {
  return offset +
         static_cast<int64_t>(rt::strings::encodeUtf8(c, rt::strings::mutableBytes(s) + offset));
}

extern "C" int64_t idris_rt_str_put_str(idris_rt_str *s, int64_t offset, const idris_rt_str *part) {
  if (part->bytes != 0)
    memcpy(rt::strings::mutableBytes(s) + offset, idris_rt_str_bytes(part), part->bytes);
  return offset + static_cast<int64_t>(part->bytes);
}

extern "C" const idris_rt_str *idris_rt_str_append(const idris_rt_str *a, const idris_rt_str *b) {
  using namespace rt::strings;
  if (a->bytes == 0)
    return shared(b);
  if (b->bytes == 0)
    return shared(a);
  idris_rt_str *s =
      newString(a->bytes + b->bytes, a->scalars + b->scalars, isAscii(a) && isAscii(b));
  memcpy(mutableBytes(s), idris_rt_str_bytes(a), a->bytes);
  memcpy(mutableBytes(s) + a->bytes, idris_rt_str_bytes(b), b->bytes);
  return s;
}

extern "C" const idris_rt_str *idris_rt_str_cons(int32_t c, const idris_rt_str *s) {
  using namespace rt::strings;
  char encoded[4];
  size_t n = encodeUtf8(c, encoded);
  idris_rt_str *result = newString(n + s->bytes, s->scalars + 1, n == 1 && isAscii(s));
  memcpy(mutableBytes(result), encoded, n);
  memcpy(mutableBytes(result) + n, idris_rt_str_bytes(s), s->bytes);
  return result;
}

extern "C" const idris_rt_str *idris_rt_str_from_char(int32_t c) {
  return idris_rt_str_cons(c, &rt::strings::emptyString);
}
