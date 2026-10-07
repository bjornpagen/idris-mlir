// rt.big:words: a big's word: a small value, tagged, or a large one's cell.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <gmp.h>

export module rt.big:words;

static_assert(sizeof(mp_limb_t) == sizeof(uint64_t), "a limb is 64 bits");
static_assert(sizeof(idris_rt_bignum) == 2 * IDRIS_RT_WORD_BYTES &&
                  alignof(idris_rt_bignum) == IDRIS_RT_WORD_BYTES,
              "a bignum's limbs start two words into its cell, aligned for a limb");
// A large big's word is its cell's address itself: cells are 8-aligned, so
// the address is even, which is the whole tag, and no other bit of the word
// is borrowed. Hardware that prefetches what looks like a heap pointer
// (Apple's and Intel's data-dependent prefetchers) then follows it.
static_assert(sizeof(idris_rt_big) == sizeof(void *) && alignof(idris_rt_header) % 2 == 0,
              "an even big word is exactly a cell address");

namespace rt::big {

inline constexpr int64_t smallMin = -(int64_t{1} << 62);
inline constexpr int64_t smallMax = (int64_t{1} << 62) - 1;
// The least magnitude that does not fit a small word, as a double. 2^62 is
// exactly a double and smallMax is not, so every double inside (-bound, bound)
// truncates into [smallMin, smallMax].
inline constexpr double smallBound = 0x1p62;
static_assert(smallBound == -static_cast<double>(smallMin));

bool isSmall(idris_rt_big a) { return (a & 1) != 0; }
int64_t smallValue(idris_rt_big a) { return a >> 1; }
bool fits(int64_t v) { return v >= smallMin && v <= smallMax; }
idris_rt_big small(int64_t v) {
  return static_cast<idris_rt_big>(static_cast<uint64_t>(v) << 1 | 1);
}

const idris_rt_bignum *bignum(idris_rt_big a) {
  return reinterpret_cast<const idris_rt_bignum *>(a);
}
// The limbs follow the bignum in its cell.
const mp_limb_t *limbsOf(const idris_rt_bignum *b) {
  return reinterpret_cast<const mp_limb_t *>(b + 1);
}

int32_t signOf(idris_rt_big a) {
  if (isSmall(a))
    return smallValue(a) < 0 ? -1 : smallValue(a) > 0 ? 1 : 0;
  int64_t size = bignum(a)->size;
  return size < 0 ? -1 : size > 0 ? 1 : 0;
}

} // namespace rt::big

extern "C" void idris_rt_big_release(idris_rt_big a) {
  idris_rt_dec(reinterpret_cast<void *>(a));
}
