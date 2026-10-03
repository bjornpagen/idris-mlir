// rt.doubles:parsing: `cast` from String to Double, as rt.numerals reads
// it.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>

#include <system_error>

#include <fast_float/fast_float.h>

export module rt.doubles:parsing;

import rt.big;
import rt.numerals;

namespace {

double fromChars(const char *p, size_t n) {
  double value = 0.0;
  auto result = fast_float::from_chars(
      p, p + n, value,
      fast_float::chars_format::general | fast_float::chars_format::allow_leading_plus);
  return result || result.ec == std::errc::result_out_of_range ? value : 0.0;
}

} // namespace

extern "C" double idris_rt_parse_double(const char *p, size_t n) {
  rt::numerals::Numeral numeral = rt::numerals::readNumeral(p, n);
  switch (numeral.kind) {
  case rt::numerals::Numeral::Infinity:
    return numeral.negative ? -__builtin_inf() : __builtin_inf();
  case rt::numerals::Numeral::NaN:
    return __builtin_nan("");
  case rt::numerals::Numeral::Decimal:
    return fromChars(p, n);
  case rt::numerals::Numeral::Integer: {
    if (numeral.base == 10 && !numeral.grouped)
      return fromChars(p, n);
    idris_rt_big magnitude =
        rt::big::bigOfDigits(p + numeral.digits, n - numeral.digits, numeral.base);
    double value = idris_rt_big_to_double(magnitude);
    idris_rt_big_release(magnitude);
    return numeral.negative ? -value : value;
  }
  case rt::numerals::Numeral::None:
    break;
  }
  return 0.0;
}

extern "C" double idris_rt_str_to_double(const idris_rt_str *s) {
  return idris_rt_parse_double(idris_rt_str_bytes(s), s->bytes);
}
