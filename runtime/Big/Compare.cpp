// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The order of two bigs.
// PIN(runtime-quarantine) — see PINS.md
#include "Big/Big.h"
#include "idris_rt.h"

#include <stdint.h>

#include <gmp.h>

using namespace rt::big;

// Two large ones are GMP's to compare, out of line (Big/Big.h).
[[gnu::noinline]] int32_t rt::big::cmpLarge(idris_rt_big a, idris_rt_big b) {
  Operand x(a), y(b);
  int c = mpz_cmp(x.get(), y.get());
  return c < 0 ? -1 : c > 0 ? 1 : 0;
}

// Tagging keeps the order: 2x + 1 < 2y + 1 exactly when x < y. Each integer
// has one representation, so a large big lies outside the small range:
// against a small one its sign alone decides, and is never 0, so an
// equality test with one small operand folds to the words' equality once
// this is inlined, with no load. Always inlined (Big/Big.h).
extern "C" [[gnu::always_inline]] int32_t idris_rt_big_cmp(idris_rt_big a, idris_rt_big b) {
  if (bothSmall(a, b)) [[likely]]
    return a < b ? -1 : a > b ? 1 : 0;
  if (isSmall(a))
    return -signOf(b);
  if (isSmall(b))
    return signOf(a);
  return cmpLarge(a, b);
}
