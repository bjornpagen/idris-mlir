// rt.strings:order: the order of two strings.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>

export module rt.strings:order;

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
