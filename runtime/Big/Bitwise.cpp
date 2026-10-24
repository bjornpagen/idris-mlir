// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The bitwise operations of bigs and their shifts: those of the infinite
// two's complement representation, as upstream Idris's test suite requires
// of every backend (its integers test of Chez, RefC and Node).
#include "Alloc/Alloc.h"
#include "End/End.h"
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
  if (!idris_rt_word_is_small(amount))
    return UINT64_MAX;
  int64_t v = idris_rt_small_value(amount);
  return v < 0 ? 0 - static_cast<uint64_t>(v) : static_cast<uint64_t>(v);
}

// a * 2^k, a new value whatever k is: a move of 0 places copies a large a,
// since the result is fresh and never the argument. GMP holds at most
// INT_MAX limbs and aborts past them, so a result that needs more is memory
// the machine cannot give: the out-of-memory ending. 0 moved any number of
// places is 0.
idris_rt_big up(idris_rt_big a, uint64_t k) {
  if (signOf(a) == 0)
    return a;
  // 2x * 2^k, tagged after: it overflows exactly when x * 2^k is not small.
  idris_rt_big product;
  if (idris_rt_word_is_small(a) && k < 63 &&
      !__builtin_mul_overflow(a - 1, idris_rt_big{1} << k, &product))
    return product + 1;
  Operand x(a);
  if (mpz_size(x.get()) + k / uint64_t{GMP_NUMB_BITS} + 1 > static_cast<uint64_t>(INT_MAX))
    rt::end::end(rt::end::OutOfMemory{});
  Result r;
  mpz_mul_2exp(r.get(), x.get(), k);
  return r.finish();
}

// floor(a / 2^k): the two's complement moved right, filling with the sign,
// a new value whatever k is, as up's is. A small word 2x + 1 moved k places
// is 2 floor(x / 2^k) plus one bit, which the tag replaces; from 63 places
// on only the sign is left. A quotient past a large one's limbs is 0 or -1.
idris_rt_big down(idris_rt_big a, uint64_t k) {
  if (idris_rt_word_is_small(a))
    return (a >> (k < 63 ? k : 63)) | 1;
  Operand x(a);
  Result r;
  mpz_fdiv_q_2exp(r.get(), x.get(), k);
  return r.finish();
}

// The way a shift moves a value by an amount that is not negative; a
// negative amount moves it the other way.
enum class Toward : uint8_t { Left, Right };

idris_rt_big shift(idris_rt_big a, idris_rt_big amount, Toward toward) {
  uint64_t k = places(amount);
  Toward moves = signOf(amount) >= 0 ? toward : toward == Toward::Left ? Toward::Right : Toward::Left;
  return moves == Toward::Left ? up(a, k) : down(a, k);
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
  return shift(a, amount, Toward::Left);
}

[[gnu::noinline]] idris_rt_big shrLarge(idris_rt_big a, idris_rt_big amount) {
  return shift(a, amount, Toward::Right);
}

} // namespace rt::big

// The bitwise and, or and xor. On small words, tagged: the tag bit is 1 in
// both, so and and or keep it, and xor clears it, which the result sets
// again.
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

// A value moved `amount` places left, the other way when the amount is
// negative, as Scheme's ash moves it: value * 2^amount, and for a negative
// amount the floor of value / 2^-amount, so it fills with the sign. A shift
// toward zero, and any shift of 0, is defined for every amount. A left shift
// whose result no integer can hold (more than 2^31 - 1 limbs) ends the
// process as exhausted memory does.
//
// A small value moved left by a small amount in [0, 63) is 2x * 2^k, tagged
// after, as up() computes it; tagged words order as their values, so the
// amount's range is tested on its word.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_shl(idris_rt_big a, idris_rt_big n) {
  idris_rt_big product;
  if (bothSmall(a, n) && n >= idris_rt_small_word(0) && n < idris_rt_small_word(63) &&
      !__builtin_mul_overflow(a - 1, idris_rt_big{1} << idris_rt_small_value(n),
                              &product)) [[likely]]
    return product + 1;
  return shlLarge(a, n);
}

// A value moved `amount` places right, as idris_rt_big_shl moves it left:
// the floor of value / 2^amount, filling with the sign.
//
// A small value moved right by a small amount that is not negative is as
// down() computes it: from 63 places on only the sign is left, and 0 places
// leave the word as it is.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_big_shr(idris_rt_big a, idris_rt_big n) {
  if (bothSmall(a, n) && n >= idris_rt_small_word(0)) [[likely]]
    return (a >> (n < idris_rt_small_word(63) ? idris_rt_small_value(n) : 63)) | 1;
  return shrLarge(a, n);
}
