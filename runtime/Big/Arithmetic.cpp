// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Sums, differences, products, quotients and remainders of bigs, negation,
// and the Nat of an Integer.
//
// Division and modulus are Euclidean: the remainder is in [0, |b|). That is
// Idris's own meaning of div and mod on Integer: upstream's test suite
// requires it of every backend, and each of Chez, RefC and Node computes
// it its own way.
// PIN(runtime-quarantine) — see PINS.md
#include "Big/Big.h"
#include "idris_rt.h"

#include <stdint.h>

#include <gmp.h>

using namespace rt::big;

namespace {

// Truncating division's remainder takes the dividend's sign. The Euclidean
// pair has the remainder in [0, |y|), so a negative remainder moves one
// quotient step the other way. y is not zero.
void euclidean(int64_t x, int64_t y, int64_t &q, int64_t &r) {
  q = x / y;
  r = x % y;
  if (r >= 0)
    return;
  if (y > 0) {
    --q;
    r += y;
  } else {
    ++q;
    r -= y;
  }
}

} // namespace

// The small paths compute on the tagged words themselves. A small word is
// 2x + 1, and the small range is exactly the 63-bit integers, so a result
// computed in tagged form overflows 64 bits exactly when the integer leaves
// the small range: the overflow flag is the one test, the result is tagged
// already, and the integers that do not fit go to the large path as any
// GMP operand does. b - 1 is even and never overflows. Each entry is
// always inlined and each large path is out of line (Big/Big.h).

namespace rt::big {

[[gnu::noinline]] idris_rt_big addLarge(idris_rt_big a, idris_rt_big b) {
  return binary(a, b, mpz_add);
}

[[gnu::noinline]] idris_rt_big subLarge(idris_rt_big a, idris_rt_big b) {
  return binary(a, b, mpz_sub);
}

[[gnu::noinline]] idris_rt_big mulLarge(idris_rt_big a, idris_rt_big b) {
  return binary(a, b, mpz_mul);
}

[[gnu::noinline]] idris_rt_big negLarge(idris_rt_big a) {
  Operand x(a);
  Result r;
  mpz_neg(r.get(), x.get());
  return r.finish();
}

// A large Integer is no small 0: a negative one is the natural 0, any other
// itself, with one more reference, since the result is owned.
[[gnu::noinline]] idris_rt_big natFromBigLarge(idris_rt_big a) {
  return signOf(a) < 0 ? small(0) : owned(a);
}

} // namespace rt::big

// (2x + 1) + 2y = 2(x + y) + 1.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_add(idris_rt_big a, idris_rt_big b) {
  idris_rt_big sum;
  if (bothSmall(a, b) && !__builtin_add_overflow(a, b - 1, &sum)) [[likely]]
    return sum;
  return addLarge(a, b);
}

// (2x + 1) - 2y = 2(x - y) + 1.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_sub(idris_rt_big a, idris_rt_big b) {
  idris_rt_big difference;
  if (bothSmall(a, b) && !__builtin_sub_overflow(a, b - 1, &difference)) [[likely]]
    return difference;
  return subLarge(a, b);
}

// The difference with 1: for a natural that is not zero, it never leaves
// the small range when the natural is small.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_pred(idris_rt_big a) {
  return idris_rt_big_sub(a, small(1));
}

// A negative integer is 0, as Idris's integerToNat; any other is itself. A
// small word's order is its value's, so a small one is the larger of its
// word and the word of 0.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_nat_from_big(idris_rt_big a) {
  if (isSmall(a)) [[likely]]
    return a > small(0) ? a : small(0);
  return natFromBigLarge(a);
}

// x * 2y = 2xy, then the tag: an even product below 2^63 takes it without
// overflow.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_mul(idris_rt_big a, idris_rt_big b) {
  idris_rt_big product;
  if (bothSmall(a, b) && !__builtin_mul_overflow(smallValue(a), b - 1, &product)) [[likely]]
    return product + 1;
  return mulLarge(a, b);
}

// The quotient of two small integers is small, but for IDRIS_RT_SMALL_MIN / -1.
extern "C" idris_rt_big idris_rt_big_div(idris_rt_big a, idris_rt_big b) {
  if (bothSmall(a, b)) {
    int64_t q, r;
    euclidean(smallValue(a), smallValue(b), q, r);
    return ofInt64(q);
  }
  return binary(a, b, signOf(b) > 0 ? mpz_fdiv_q : mpz_cdiv_q);
}

// A remainder is below the divisor's magnitude, so small.
extern "C" idris_rt_big idris_rt_big_mod(idris_rt_big a, idris_rt_big b) {
  if (bothSmall(a, b)) {
    int64_t q, r;
    euclidean(smallValue(a), smallValue(b), q, r);
    return small(r);
  }
  return binary(a, b, mpz_mod);
}

// 2 - (2x + 1) = 2(-x) + 1, which overflows for IDRIS_RT_SMALL_MIN alone.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_neg(idris_rt_big a) {
  idris_rt_big negated;
  if (isSmall(a) && !__builtin_sub_overflow(idris_rt_big{2}, a, &negated)) [[likely]]
    return negated;
  return negLarge(a);
}
