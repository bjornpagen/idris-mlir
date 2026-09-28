// `cast` from String (TC-RT-4; docs/plan.md section 3). Idris fixes the
// frame: the whole string is read, and a string that is not a number is 0.
// Which strings are numbers is ours to define (idris_rt.h):
// - to Double: the whole string in fast_float's general format, with a
//   leading `+` allowed, correctly rounded to nearest-even. An exponent out of
//   range gives the infinity or zero fast_float stores alongside its range
//   error. Anything else, surrounding spaces, `1d3`, `1/2`, `0x10` and
//   `1_000` included, is 0.
// - to an integer: a sign and decimal digits are that integer, exactly, as
//   Chez reads them; another string the Double cast accepts is its finite
//   value truncated toward zero, as Chez's exact-truncate does. The
//   infinities and NaN, which Chez's exact-truncate refuses, are 0.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <system_error>

#include <fast_float/fast_float.h>

extern "C" double idris_rt_parse_double(const char *p, size_t n) {
  const char *last = p + n;
  double value = 0.0;
  auto result = fast_float::from_chars(p, last, value,
                                       fast_float::chars_format::general |
                                           fast_float::chars_format::allow_leading_plus);
  if (result.ptr != last)
    return 0.0;
  if (result || result.ec == std::errc::result_out_of_range)
    return value;
  return 0.0;
}

bool rt::isInteger(const char *p, size_t n, size_t &digits) {
  digits = n > 0 && (p[0] == '+' || p[0] == '-') ? 1 : 0;
  if (digits == n)
    return false;
  for (size_t i = digits; i < n; ++i)
    if (p[i] < '0' || p[i] > '9')
      return false;
  return true;
}

extern "C" double idris_rt_str_to_double(const idris_rt_str *s) {
  return idris_rt_parse_double(idris_rt_str_bytes(s), s->bytes);
}

extern "C" int64_t idris_rt_str_to_int(const idris_rt_str *s) {
  const char *p = idris_rt_str_bytes(s);
  size_t digits;
  if (rt::isInteger(p, s->bytes, digits)) {
    uint64_t value = 0;
    for (size_t i = digits; i < s->bytes; ++i)
      value = 10 * value + static_cast<uint64_t>(p[i] - '0');
    return static_cast<int64_t>(p[0] == '-' ? 0 - value : value);
  }
  double value = idris_rt_parse_double(p, s->bytes);
  return __builtin_isfinite(value) ? idris_rt_to_int(value) : 0;
}
