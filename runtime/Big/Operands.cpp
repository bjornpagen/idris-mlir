// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Bigs as GMP reads and writes them: a view of an operand, and a result
// given its one representation; and a machine integer's large big, which
// no GMP operation writes.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Big/Big.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <gmp.h>

namespace {

// A large big's cell for `count` limbs, its size and limbs for the caller
// to write.
idris_rt_bignum *newBignum(size_t count) {
  return static_cast<idris_rt_bignum *>(
      rt::alloc::newCell(sizeof(idris_rt_bignum) + count * sizeof(mp_limb_t),
                         idris_rt_info(0, 0, IDRIS_RT_KIND_BIGNUM)));
}

// The limbs a 64-bit magnitude takes. A magnitude no small word holds is at
// least 2^62, so its top limb is never zero and every such big takes
// exactly this many.
constexpr size_t wordLimbs = (64 + GMP_NUMB_BITS - 1) / GMP_NUMB_BITS;
static_assert((wordLimbs - 1) * GMP_NUMB_BITS <= 62,
              "a 64-bit magnitude outside the small range fills its top limb");

// The large big of a 64-bit magnitude, `size` its limbs with their sign:
// written straight into its cell, so the cell, which the result names, is
// the only memory it takes.
idris_rt_big largeOfMagnitude(uint64_t magnitude, int64_t size) {
  idris_rt_bignum *b = newBignum(wordLimbs);
  b->size = size;
  auto *limbs = reinterpret_cast<mp_limb_t *>(b + 1);
  for (size_t i = 0; i < wordLimbs; ++i)
    limbs[i] = static_cast<mp_limb_t>(magnitude >> (i * GMP_NUMB_BITS)) & GMP_NUMB_MASK;
  return reinterpret_cast<idris_rt_big>(b);
}

} // namespace

namespace rt::big {

Operand::Operand(idris_rt_big a) {
  if (!idris_rt_word_is_small(a)) {
    const idris_rt_bignum *b = bignum(a);
    mpz_roinit_n(&view, limbsOf(b), static_cast<mp_size_t>(b->size));
    return;
  }
  int64_t v = idris_rt_small_value(a);
  limb = v < 0 ? 0 - static_cast<uint64_t>(v) : static_cast<uint64_t>(v);
  mpz_roinit_n(&view, &limb, v < 0 ? -1 : v > 0 ? 1 : 0);
}

Result::Result() { mpz_init(&value); }

idris_rt_big Result::finish() {
  if (mpz_fits_slong_p(&value) && fits(mpz_get_si(&value))) {
    int64_t v = mpz_get_si(&value);
    mpz_clear(&value);
    return idris_rt_small_word(v);
  }
  size_t count = mpz_size(&value);
  idris_rt_bignum *b = newBignum(count);
  auto size = static_cast<int64_t>(count);
  b->size = mpz_sgn(&value) < 0 ? -size : size;
  memcpy(b + 1, mpz_limbs_read(&value), count * sizeof(mp_limb_t));
  mpz_clear(&value);
  return reinterpret_cast<idris_rt_big>(b);
}

[[gnu::noinline]] idris_rt_big largeOfInt64(int64_t v) {
  constexpr auto limbs = static_cast<int64_t>(wordLimbs);
  return v < 0 ? largeOfMagnitude(0 - static_cast<uint64_t>(v), -limbs)
               : largeOfMagnitude(static_cast<uint64_t>(v), limbs);
}

[[gnu::noinline]] idris_rt_big fromUnsignedLarge(uint64_t value) {
  return largeOfMagnitude(value, static_cast<int64_t>(wordLimbs));
}

} // namespace rt::big
