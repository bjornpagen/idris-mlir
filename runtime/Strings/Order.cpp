// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The order of two strings.
// PIN(runtime-quarantine) — see PINS.md
#include "idris_rt.h"

#include <stdint.h>
#include <string.h>

// -1, 0 or 1 as the first string is before, equal to or after the second in
// the order of their scalar values, Unicode's code point order. UTF-8's byte
// order is that order, and memcmp compares bytes as unsigned char, the C
// library's vectorized loop. Equal common bytes leave the shorter string
// first.
extern "C" int32_t idris_rt_str_cmp(const idris_rt_str *a, const idris_rt_str *b) {
  uint64_t n = a->bytes < b->bytes ? a->bytes : b->bytes;
  int c = memcmp(idris_rt_str_bytes(a), idris_rt_str_bytes(b), n);
  if (c != 0)
    return c < 0 ? -1 : 1;
  return a->bytes < b->bytes ? -1 : a->bytes > b->bytes ? 1 : 0;
}
