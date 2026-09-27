// `cast` from String to Double over fast_float (TC-RT-1; docs/plan.md
// section 3). Idris fixes the frame: the whole string is read, and a string
// that is not a number is 0. Which strings are numbers is ours to define:
// the whole string in fast_float's general format, with a leading `+`
// allowed, correctly rounded to nearest-even. An exponent out of range gives
// the infinity or zero fast_float stores alongside its range error. Anything
// else, surrounding spaces, `1d3`, `1/2`, `0x10` and `1_000` included, is 0.
// PIN(runtime-quarantine) — see PINS.md

#include "idris_rt.h"

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
