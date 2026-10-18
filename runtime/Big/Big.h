// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::big: bigs, Integer and the Nat-like types. A value that fits in 63
// bits is a tagged word, and any other is a GMP integer, so each integer has
// one representation; every operation returns the small form when the
// result fits.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "Rc/Rc.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

#include <gmp.h>

namespace rt::big {

// A big's word: a small value, tagged, in the small range
// (IDRIS_RT_SMALL_MIN to IDRIS_RT_SMALL_MAX), or a large one's cell
// (Words.cpp checks the layout this reads).
//
// The least magnitude that does not fit a small word, as a double. 2^62 is
// exactly a double and IDRIS_RT_SMALL_MAX is not, so every double inside
// (-bound, bound) truncates into the small range.
inline constexpr double smallBound = 0x1p62;
static_assert(smallBound == -static_cast<double>(IDRIS_RT_SMALL_MIN));

// Both small, in one test of the two words' tag bits.
inline bool bothSmall(idris_rt_big a, idris_rt_big b) { return idris_rt_word_is_small(a & b); }
inline bool fits(int64_t v) { return v >= IDRIS_RT_SMALL_MIN && v <= IDRIS_RT_SMALL_MAX; }

inline const idris_rt_bignum *bignum(idris_rt_big a) {
  return reinterpret_cast<const idris_rt_bignum *>(a);
}
// The limbs follow the bignum in its cell.
inline const mp_limb_t *limbsOf(const idris_rt_bignum *b) {
  return reinterpret_cast<const mp_limb_t *>(b + 1);
}

// A large big is never 0, which is small: its size's sign is its own.
inline int32_t signOf(idris_rt_big a) {
  if (idris_rt_word_is_small(a))
    return idris_rt_small_value(a) < 0 ? -1 : idris_rt_small_value(a) > 0 ? 1 : 0;
  return bignum(a)->size < 0 ? -1 : 1;
}

// A reference to `a` itself that the caller owns: a small big is its word,
// and a large one gets one more reference.
inline idris_rt_big owned(idris_rt_big a) {
  if (!idris_rt_word_is_small(a))
    rt::rc::incCell(bignum(a));
  return a;
}

// Drops a reference the caller owns; a small big is an odd word, which
// counting leaves alone.
inline void release(idris_rt_big a) { rt::rc::dec(reinterpret_cast<const void *>(a)); }

// Bigs as GMP reads and writes them (Operands.cpp).

// A read-only GMP view of any big, which copies nothing: a large one's limbs
// in its cell, or a small one's value in one limb on the stack.
struct Operand {
  mp_limb_t limb;
  __mpz_struct view;

  explicit Operand(idris_rt_big a);
  mpz_srcptr get() const { return &view; }
};

// The integer a GMP operation writes, on the stack, through GMP's
// allocator, which idris_rt_start has set. finish gives it its one
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

// A machine integer as a big: its small word, inline, or a large one, which
// only a value outside 63 bits needs (Operands.cpp).
idris_rt_big largeOfInt64(int64_t v);
inline idris_rt_big ofInt64(int64_t v) {
  return fits(v) ? idris_rt_small_word(v) : largeOfInt64(v);
}

// The ops whose small case is a word op are split in two. The C entry is
// the small path, always inlined wherever the runtime's bitcode is joined:
// a program's call with small operands is the overflow-checked word op and
// a branch, with nothing else to call, and idr-lower calls the entry rather
// than restating it, so the small case exists once. When an operand is a
// GMP integer or the result leaves the small range, the entry tail-calls
// the op's large path here, out of line, so that the entry stays that
// small. They take any bigs, small ones included.
idris_rt_big addLarge(idris_rt_big a, idris_rt_big b);
idris_rt_big subLarge(idris_rt_big a, idris_rt_big b);
idris_rt_big mulLarge(idris_rt_big a, idris_rt_big b);
idris_rt_big negLarge(idris_rt_big a);
idris_rt_big natFromBigLarge(idris_rt_big a);
idris_rt_big andLarge(idris_rt_big a, idris_rt_big b);
idris_rt_big orLarge(idris_rt_big a, idris_rt_big b);
idris_rt_big xorLarge(idris_rt_big a, idris_rt_big b);
idris_rt_big shlLarge(idris_rt_big a, idris_rt_big amount);
idris_rt_big shrLarge(idris_rt_big a, idris_rt_big amount);
int32_t cmpLarge(idris_rt_big a, idris_rt_big b);
idris_rt_big fromUnsignedLarge(uint64_t value);

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
