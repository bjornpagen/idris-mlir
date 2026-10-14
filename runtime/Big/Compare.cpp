// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The order of two bigs.
// PIN(runtime-quarantine) — see PINS.md
#include "Big/Big.h"
#include "idris_rt.h"

#include <stdint.h>

#include <gmp.h>

using namespace rt::big;

extern "C" int32_t idris_rt_big_cmp(idris_rt_big a, idris_rt_big b) {
  if (isSmall(a) && isSmall(b))
    return smallValue(a) < smallValue(b) ? -1 : smallValue(a) > smallValue(b) ? 1 : 0;
  Operand x(a), y(b);
  int c = mpz_cmp(x.get(), y.get());
  return c < 0 ? -1 : c > 0 ? 1 : 0;
}
