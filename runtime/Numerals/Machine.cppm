// rt.numerals:machine: `cast` from String to a machine integer: its value
// modulo 2^64.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>

export module rt.numerals:machine;

import :reading;

extern "C" int64_t idris_rt_str_to_int(const idris_rt_str *s) {
  const char *p = idris_rt_str_bytes(s);
  rt::numerals::Numeral numeral = rt::numerals::readNumeral(p, s->bytes);
  if (numeral.kind != rt::numerals::Numeral::Integer)
    return 0;
  return static_cast<int64_t>(numeral.wrapped(p, s->bytes));
}
