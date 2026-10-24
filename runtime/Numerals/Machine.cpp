// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// `cast` from String to a machine integer: its value modulo 2^64.
#include "Numerals/Numerals.h"
#include "idris_rt.h"

#include <stdint.h>

// An integer literal's value modulo 2^64, which idr-lower wraps to the op's
// width; any other string is 0 (rt::numerals::readNumeral).
extern "C" int64_t idris_rt_str_to_int(const idris_rt_str *s) {
  const char *p = idris_rt_str_bytes(s);
  rt::numerals::Numeral numeral = rt::numerals::readNumeral(p, s->bytes);
  if (numeral.kind != rt::numerals::Numeral::Integer)
    return 0;
  return static_cast<int64_t>(numeral.wrapped(p, s->bytes));
}
