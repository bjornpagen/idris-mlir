// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Bigs as GMP reads and writes them: a view of an operand, and a result
// given its one representation.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Big/Big.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <gmp.h>

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
  auto *b = static_cast<idris_rt_bignum *>(rt::alloc::newCell(
      sizeof(idris_rt_bignum) + count * sizeof(mp_limb_t), idris_rt_info(0, 0, IDRIS_RT_KIND_BIGNUM)));
  auto size = static_cast<int64_t>(count);
  b->size = mpz_sgn(&value) < 0 ? -size : size;
  memcpy(b + 1, mpz_limbs_read(&value), count * sizeof(mp_limb_t));
  mpz_clear(&value);
  return reinterpret_cast<idris_rt_big>(b);
}

[[gnu::noinline]] idris_rt_big largeOfInt64(int64_t v) {
  Result r;
  mpz_set_si(r.get(), v);
  return r.finish();
}

} // namespace rt::big
