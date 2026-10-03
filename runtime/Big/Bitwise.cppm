// rt.big:bitwise: the bitwise operations of bigs, in two's complement.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <gmp.h>

export module rt.big:bitwise;

import :operands;
import :words;

using namespace rt::big;

extern "C" idris_rt_big idris_rt_big_and(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return small(smallValue(a) & smallValue(b));
  return binary(a, b, mpz_and);
}

extern "C" idris_rt_big idris_rt_big_or(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return small(smallValue(a) | smallValue(b));
  return binary(a, b, mpz_ior);
}

extern "C" idris_rt_big idris_rt_big_xor(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return small(smallValue(a) ^ smallValue(b));
  return binary(a, b, mpz_xor);
}
