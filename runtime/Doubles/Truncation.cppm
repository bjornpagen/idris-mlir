// rt.doubles:truncation: a double as a machine integer.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>

export module rt.doubles:truncation;

import :ieee;

// |x| = m * 2^e, truncated by shifting; then the sign, modulo 2^64.
extern "C" int64_t idris_rt_to_int(double x) {
  using namespace rt::doubles;
  uint64_t bits = bitsOf(x);
  uint64_t exponent = (bits >> mantissaBits) & exponentMask;
  uint64_t m = exponent == 0 ? bits & mantissaMask : (bits & mantissaMask) | (uint64_t{1} << mantissaBits);
  // The significand's least bit has weight 2^(exponent - bias - mantissa bits).
  int64_t e = static_cast<int64_t>(exponent) - exponentBias - static_cast<int64_t>(mantissaBits);
  uint64_t magnitude;
  if (e >= 0)
    magnitude = e >= 64 ? 0 : m << e;
  else
    magnitude = -e >= 64 ? 0 : m >> -e;
  return static_cast<int64_t>((bits >> 63) != 0 ? 0 - magnitude : magnitude);
}
