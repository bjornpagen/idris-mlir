// rt::big: bigs, Integer and the Nat-like types. A value that fits in 63
// bits is a tagged word, and any other is a GMP integer, so each integer has
// one representation; every operation returns the small form when the
// result fits.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

#include <gmp.h>

namespace rt::big {

// A big's word: a small value, tagged, or a large one's cell (Words.cpp
// checks the layout this reads).
inline constexpr int64_t smallMin = -(int64_t{1} << 62);
inline constexpr int64_t smallMax = (int64_t{1} << 62) - 1;
// The least magnitude that does not fit a small word, as a double. 2^62 is
// exactly a double and smallMax is not, so every double inside (-bound, bound)
// truncates into [smallMin, smallMax].
inline constexpr double smallBound = 0x1p62;
static_assert(smallBound == -static_cast<double>(smallMin));

inline bool isSmall(idris_rt_big a) { return (a & 1) != 0; }
inline int64_t smallValue(idris_rt_big a) { return a >> 1; }
inline bool fits(int64_t v) { return v >= smallMin && v <= smallMax; }
inline idris_rt_big small(int64_t v) {
  return static_cast<idris_rt_big>(static_cast<uint64_t>(v) << 1 | 1);
}

inline const idris_rt_bignum *bignum(idris_rt_big a) {
  return reinterpret_cast<const idris_rt_bignum *>(a);
}
// The limbs follow the bignum in its cell.
inline const mp_limb_t *limbsOf(const idris_rt_bignum *b) {
  return reinterpret_cast<const mp_limb_t *>(b + 1);
}

inline int32_t signOf(idris_rt_big a) {
  if (isSmall(a))
    return smallValue(a) < 0 ? -1 : smallValue(a) > 0 ? 1 : 0;
  int64_t size = bignum(a)->size;
  return size < 0 ? -1 : size > 0 ? 1 : 0;
}

// A reference to `a` itself that the caller owns: a small big is its word,
// and a large one gets one more reference.
inline idris_rt_big owned(idris_rt_big a) {
  if (!isSmall(a))
    idris_rt_inc(reinterpret_cast<void *>(a));
  return a;
}

// Bigs as GMP reads and writes them (Operands.cpp).

// A read-only GMP view of any big, which copies nothing: a large one's limbs
// in its cell, or a small one's value in one limb on the stack.
struct Operand {
  mp_limb_t limb;
  __mpz_struct view;

  explicit Operand(idris_rt_big a);
  mpz_srcptr get() const { return &view; }
};

// The integer a GMP operation writes, on the stack. finish gives it its one
// representation: a small word, or, only when it does not fit one, a new
// cell of exactly its size that its limbs are copied into, so a small result
// allocates no cell and a large one allocates one.
class Result {
public:
  Result();
  Result(const Result &) = delete;
  Result &operator=(const Result &) = delete;

  mpz_ptr get() { return &value; }

  idris_rt_big finish();

private:
  __mpz_struct value;
};

idris_rt_big ofInt64(int64_t v);

template <typename Op> idris_rt_big binary(idris_rt_big a, idris_rt_big b, Op op) {
  Operand x(a), y(b);
  Result r;
  op(r.get(), x.get(), y.get());
  return r.finish();
}

// The natural number the n bytes at p write in `base`, digits that
// underscores may separate (Digits.cpp).
idris_rt_big bigOfDigits(const char *p, size_t n, unsigned base);

} // namespace rt::big
