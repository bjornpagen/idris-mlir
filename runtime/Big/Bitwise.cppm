// rt.big:bitwise: the bitwise operations of bigs, in two's complement, and
// their shifts.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <limits.h>
#include <stdint.h>

#include <gmp.h>

export module rt.big:bitwise;

import rt.alloc;
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

namespace {

// How many places a shift moves, saturated: a large amount moves any big
// out entirely, or past what any integer can hold.
uint64_t places(idris_rt_big amount) {
  if (!isSmall(amount))
    return UINT64_MAX;
  int64_t v = smallValue(amount);
  return v < 0 ? 0 - static_cast<uint64_t>(v) : static_cast<uint64_t>(v);
}

// a * 2^k. GMP holds at most INT_MAX limbs and aborts past them, so a result
// that needs more is exhausted memory, the crash any allocation that fails is.
idris_rt_big up(idris_rt_big a, uint64_t k) {
  if (k == 0 || signOf(a) == 0)
    return owned(a);
  int64_t product;
  if (isSmall(a) && k < 63 && !__builtin_mul_overflow(smallValue(a), int64_t{1} << k, &product))
    return ofInt64(product);
  Operand x(a);
  if (mpz_size(x.get()) + k / uint64_t{GMP_NUMB_BITS} + 1 > static_cast<uint64_t>(INT_MAX))
    rt::alloc::outOfMemory();
  Result r;
  mpz_mul_2exp(r.get(), x.get(), k);
  return r.finish();
}

// floor(a / 2^k): the two's complement moved right, filling with the sign.
// A small value is within 63 bits, so from 62 places on only its sign is
// left; a quotient past a large one's limbs is 0 or -1.
idris_rt_big down(idris_rt_big a, uint64_t k) {
  if (k == 0)
    return owned(a);
  if (isSmall(a))
    return small(smallValue(a) >> (k < 62 ? k : 62));
  Operand x(a);
  Result r;
  mpz_fdiv_q_2exp(r.get(), x.get(), k);
  return r.finish();
}

// `a` moved by `amount` places: left when `left`, the other way when the
// amount is negative, as Scheme's ash moves it.
idris_rt_big shift(idris_rt_big a, idris_rt_big amount, bool left) {
  uint64_t k = places(amount);
  return left == (signOf(amount) >= 0) ? up(a, k) : down(a, k);
}

} // namespace

extern "C" idris_rt_big idris_rt_big_shl(idris_rt_big a, idris_rt_big n) {
  return shift(a, n, true);
}

extern "C" idris_rt_big idris_rt_big_shr(idris_rt_big a, idris_rt_big n) {
  return shift(a, n, false);
}
