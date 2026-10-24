// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The C ABI's scalar count, over the target's simdutf implementation.
#include "Strings/Simd.h"
#include "idris_rt.h"

#include <stddef.h>

// The number of scalar values in n bytes of well-formed UTF-8: what a
// string's scalar count is, for a string idr-lower writes into static data.
extern "C" size_t idris_rt_utf8_count(const char *p, size_t n) {
  return rt::strings::utf8.count_utf8(p, n);
}
