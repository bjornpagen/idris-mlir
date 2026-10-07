// rt.big:conversions: bigs from and to machine integers and doubles.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

#include <gmp.h>

export module rt.big:conversions;

import :operands;
import :words;

using namespace rt::big;

extern "C" idris_rt_big idris_rt_big_from_int_s(int64_t value) { return ofInt64(value); }

extern "C" idris_rt_big idris_rt_big_from_int_u(uint64_t value) {
  if (value <= static_cast<uint64_t>(smallMax))
    return small(static_cast<int64_t>(value));
  Result r;
  mpz_set_ui(r.get(), value);
  return r.finish();
}

extern "C" int64_t idris_rt_big_to_int(idris_rt_big a) {
  if (isSmall(a))
    return smallValue(a);
  Operand x(a);
  uint64_t low = mpz_getlimbn(x.get(), 0);
  return static_cast<int64_t>(mpz_sgn(x.get()) < 0 ? 0 - low : low);
}

extern "C" idris_rt_big idris_rt_big_from_double(double x) {
  if (x > -smallBound && x < smallBound)
    return small(static_cast<int64_t>(x));
  Result r;
  mpz_set_d(r.get(), x);
  return r.finish();
}

// IEEE 754's conversion under its default rounding: the nearest double,
// ties to even, and an infinity past the largest. GMP's mpz_get_d
// truncates instead, as RefC's cast does. The top 64 bits of |a|, with a
// sticky bit for any bit below them, convert with one correct rounding, and
// the scaling by a power of two is exact or overflows to the infinity.
extern "C" double idris_rt_big_to_double(idris_rt_big a) {
  if (isSmall(a))
    return static_cast<double>(smallValue(a));
  Operand x(a);
  mpz_srcptr z = x.get();
  size_t bits = mpz_sizeinbase(z, 2);
  if (bits <= 64) {
    auto magnitude = static_cast<double>(mpz_getlimbn(z, 0));
    return mpz_sgn(z) < 0 ? -magnitude : magnitude;
  }
  size_t shift = bits - 64;
  size_t limb = shift / 64;
  unsigned offset = static_cast<unsigned>(shift % 64);
  uint64_t top = mpz_getlimbn(z, static_cast<mp_size_t>(limb)) >> offset;
  if (offset != 0)
    top |= mpz_getlimbn(z, static_cast<mp_size_t>(limb + 1)) << (64 - offset);
  bool sticky = offset != 0 && (mpz_getlimbn(z, static_cast<mp_size_t>(limb)) &
                                ((uint64_t{1} << offset) - 1)) != 0;
  for (size_t i = 0; i < limb && !sticky; ++i)
    sticky = mpz_getlimbn(z, static_cast<mp_size_t>(i)) != 0;
  double magnitude = __builtin_ldexp(static_cast<double>(top | (sticky ? 1 : 0)),
                                     static_cast<int>(shift));
  return mpz_sgn(z) < 0 ? -magnitude : magnitude;
}
