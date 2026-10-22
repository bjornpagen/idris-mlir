// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A big's word: a small value, tagged, or a large one's cell. The small
// value's word is made here and read by idris_rt.h's inline tests; the
// accessors of a large one are inline in Big/Big.h, and the layout they read
// is checked here.
// PIN(runtime-quarantine) — see PINS.md
#include "Big/Big.h"
#include "idris_rt.h"

#include <stdint.h>

#include <gmp.h>

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

// A small value's word, 2v + 1, for a v in the small range: idr.big.small's,
// whose operand narrowing proved small, and every small result's. Always
// inlined wherever the runtime's bitcode is joined, so the word is a shift
// and an or in the caller.
extern "C" [[gnu::always_inline]] idris_rt_big idris_rt_small_word(int64_t value) {
  return static_cast<idris_rt_big>(static_cast<uint64_t>(value) << 1 | 1);
}
