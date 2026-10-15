// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A big's word: a small value, tagged, or a large one's cell. The accessors
// are inline in Big/Big.h; the layout they read is checked here.
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

extern "C" void idris_rt_big_release(idris_rt_big a) { rt::big::release(a); }
