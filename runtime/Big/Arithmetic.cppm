// rt.big:arithmetic: sums, differences, products, quotients and remainders
// of bigs, negation, and the Nat of an Integer.
//
// Division and modulus are Euclidean: the remainder is in [0, |b|). That is
// Idris's own meaning of div and mod on Integer: upstream's test suite
// requires it of every backend, and each of Chez, RefC and Node computes
// it its own way.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>

#include <gmp.h>

export module rt.big:arithmetic;

import :operands;
import :words;

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

extern "C" idris_rt_big idris_rt_big_add(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return ofInt64(smallValue(a) + smallValue(b));
  return binary(a, b, mpz_add);
}

extern "C" idris_rt_big idris_rt_big_sub(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return ofInt64(smallValue(a) - smallValue(b));
  return binary(a, b, mpz_sub);
}

extern "C" idris_rt_big idris_rt_big_pred(idris_rt_big a) {
  return idris_rt_big_sub(a, small(1));
}

// A negative integer is 0, as Idris's integerToNat; any other is itself,
// with one more reference, since the result is owned.
extern "C" idris_rt_big idris_rt_nat_from_big(idris_rt_big a) {
  if (signOf(a) < 0)
    return small(0);
  if (!isSmall(a))
    idris_rt_inc(reinterpret_cast<void *>(a));
  return a;
}

extern "C" idris_rt_big idris_rt_big_mul(idris_rt_big a, idris_rt_big b) {
  int64_t product;
  if (isSmall(a) && isSmall(b) && !__builtin_mul_overflow(smallValue(a), smallValue(b), &product))
    return ofInt64(product);
  return binary(a, b, mpz_mul);
}

extern "C" idris_rt_big idris_rt_big_div(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b)) {
    int64_t q, r;
    euclidean(smallValue(a), smallValue(b), q, r);
    return ofInt64(q);
  }
  return binary(a, b, signOf(b) > 0 ? mpz_fdiv_q : mpz_cdiv_q);
}

extern "C" idris_rt_big idris_rt_big_mod(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b)) {
    int64_t q, r;
    euclidean(smallValue(a), smallValue(b), q, r);
    return small(r);
  }
  return binary(a, b, mpz_mod);
}

extern "C" idris_rt_big idris_rt_big_neg(idris_rt_big a) {
  if (isSmall(a))
    return ofInt64(-smallValue(a));
  Operand x(a);
  Result r;
  mpz_neg(r.get(), x.get());
  return r.finish();
}
