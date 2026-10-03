// rt.big:operands: bigs as GMP reads and writes them: a view of an operand,
// and a result given its one representation.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <gmp.h>

export module rt.big:operands;

import rt.alloc;
import :words;

namespace rt::big {

// A read-only GMP view of any big, which copies nothing: a large one's limbs
// in its cell, or a small one's value in one limb on the stack.
struct Operand {
  mp_limb_t limb;
  __mpz_struct view;

  explicit Operand(idris_rt_big a) {
    if (!isSmall(a)) {
      const idris_rt_bignum *b = bignum(a);
      mpz_roinit_n(&view, limbsOf(b), static_cast<mp_size_t>(b->size));
      return;
    }
    int64_t v = smallValue(a);
    limb = v < 0 ? 0 - static_cast<uint64_t>(v) : static_cast<uint64_t>(v);
    mpz_roinit_n(&view, &limb, v < 0 ? -1 : v > 0 ? 1 : 0);
  }
  mpz_srcptr get() const { return &view; }
};

// The integer a GMP operation writes, on the stack. finish gives it its one
// representation: a small word, or, only when it does not fit one, a new
// cell of exactly its size that its limbs are copied into, so a small result
// allocates no cell and a large one allocates one.
class Result {
public:
  Result() {
    rt::alloc::gmpReady();
    mpz_init(&value);
  }
  Result(const Result &) = delete;
  Result &operator=(const Result &) = delete;

  mpz_ptr get() { return &value; }

  idris_rt_big finish() {
    if (mpz_fits_slong_p(&value) && fits(mpz_get_si(&value))) {
      int64_t v = mpz_get_si(&value);
      mpz_clear(&value);
      return small(v);
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

private:
  __mpz_struct value;
};

idris_rt_big ofInt64(int64_t v) {
  if (fits(v))
    return small(v);
  Result r;
  mpz_set_si(r.get(), v);
  return r.finish();
}

template <typename Op> idris_rt_big binary(idris_rt_big a, idris_rt_big b, Op op) {
  Operand x(a), y(b);
  Result r;
  op(r.get(), x.get(), y.get());
  return r.finish();
}

} // namespace rt::big
