// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The bitwise operations of bigs, in two's complement, and their shifts.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Big/Big.h"
#include "idris_rt.h"

#include <limits.h>
#include <stdint.h>

#include <gmp.h>

using namespace rt::big;

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
  // 2x * 2^k, tagged after: it overflows exactly when x * 2^k is not small.
  idris_rt_big product;
  if (isSmall(a) && k < 63 && !__builtin_mul_overflow(a - 1, idris_rt_big{1} << k, &product))
    return product + 1;
  Operand x(a);
  if (mpz_size(x.get()) + k / uint64_t{GMP_NUMB_BITS} + 1 > static_cast<uint64_t>(INT_MAX))
    rt::alloc::outOfMemory();
  Result r;
  mpz_mul_2exp(r.get(), x.get(), k);
  return r.finish();
}

// floor(a / 2^k): the two's complement moved right, filling with the sign.
// A small word 2x + 1 moved k >= 1 places is 2 floor(x / 2^k) plus one bit,
// which the tag replaces; from 63 places on only the sign is left. A
// quotient past a large one's limbs is 0 or -1.
idris_rt_big down(idris_rt_big a, uint64_t k) {
  if (k == 0)
    return owned(a);
  if (isSmall(a))
    return (a >> (k < 63 ? k : 63)) | 1;
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

// The large paths take any bigs, small ones included (Big/Big.h).
namespace rt::big {

[[gnu::noinline]] idris_rt_big andLarge(idris_rt_big a, idris_rt_big b) {
  return binary(a, b, mpz_and);
}

[[gnu::noinline]] idris_rt_big orLarge(idris_rt_big a, idris_rt_big b) {
  return binary(a, b, mpz_ior);
}

[[gnu::noinline]] idris_rt_big xorLarge(idris_rt_big a, idris_rt_big b) {
  return binary(a, b, mpz_xor);
}

[[gnu::noinline]] idris_rt_big shlLarge(idris_rt_big a, idris_rt_big amount) {
  return shift(a, amount, true);
}

[[gnu::noinline]] idris_rt_big shrLarge(idris_rt_big a, idris_rt_big amount) {
  return shift(a, amount, false);
}

} // namespace rt::big

// On small words, tagged: the tag bit is 1 in both, so and and or keep it,
// and xor clears it, which the result sets again.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_and(idris_rt_big a, idris_rt_big b) {
  if (bothSmall(a, b)) [[likely]]
    return a & b;
  return andLarge(a, b);
}

extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_or(idris_rt_big a, idris_rt_big b) {
  if (bothSmall(a, b)) [[likely]]
    return a | b;
  return orLarge(a, b);
}

extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_xor(idris_rt_big a, idris_rt_big b) {
  if (bothSmall(a, b)) [[likely]]
    return (a ^ b) | 1;
  return xorLarge(a, b);
}

// A small value moved left by a small amount in [0, 63): 2x * 2^k, tagged
// after, as up() computes it; tagged words order as their values, so the
// amount's range is tested on its word.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_shl(idris_rt_big a, idris_rt_big n) {
  idris_rt_big product;
  if (bothSmall(a, n) && n >= small(0) && n < small(63) &&
      !__builtin_mul_overflow(a - 1, idris_rt_big{1} << smallValue(n), &product)) [[likely]]
    return product + 1;
  return shlLarge(a, n);
}

// A small value moved right by a small amount that is not negative, as
// down() computes it: from 63 places on only the sign is left, and 0
// places leave the word as it is.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_shr(idris_rt_big a, idris_rt_big n) {
  if (bothSmall(a, n) && n >= small(0)) [[likely]]
    return (a >> (n < small(63) ? smallValue(n) : 63)) | 1;
  return shrLarge(a, n);
}
