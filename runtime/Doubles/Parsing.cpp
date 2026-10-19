// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// `cast` from String to Double, as rt::numerals reads it.
// PIN(runtime-quarantine) — see PINS.md
#include "Big/Big.h"
#include "Numerals/Numerals.h"
#include "idris_rt.h"

#include <stddef.h>

#include <system_error>

#include <fast_float/fast_float.h>

namespace {

double fromChars(const char *p, size_t n) {
  double value = 0.0;
  auto result = fast_float::from_chars(
      p, p + n, value,
      fast_float::chars_format::general | fast_float::chars_format::allow_leading_plus);
  return result || result.ec == std::errc::result_out_of_range ? value : 0.0;
}

} // namespace

// The nearest double to the number the string writes, ties to even; any
// other string is 0.0 (rt::numerals::readNumeral).
extern "C" double idris_rt_str_to_double(const idris_rt_str *s) {
  const char *p = idris_rt_str_bytes(s);
  size_t n = s->bytes;
  rt::numerals::Numeral numeral = rt::numerals::readNumeral(p, n);
  switch (numeral.kind) {
  case rt::numerals::Numeral::Infinity:
    return numeral.negative ? -__builtin_inf() : __builtin_inf();
  case rt::numerals::Numeral::NaN:
    return __builtin_nan("");
  case rt::numerals::Numeral::Decimal:
    return fromChars(p, n);
  case rt::numerals::Numeral::Integer: {
    // The integer's magnitude, then its sign as an integer's: 0 - x, which
    // is 0 for 0, since an integer has no negative zero.
    double magnitude;
    if (numeral.base == 10 && !numeral.grouped) {
      magnitude = fromChars(p + numeral.digits, n - numeral.digits);
    } else {
      idris_rt_big big =
          rt::big::bigOfDigits(p + numeral.digits, n - numeral.digits, numeral.base);
      magnitude = idris_rt_big_to_double(big);
      rt::big::release(big);
    }
    return numeral.negative ? 0.0 - magnitude : magnitude;
  }
  case rt::numerals::Numeral::None:
    break;
  }
  return 0.0;
}
