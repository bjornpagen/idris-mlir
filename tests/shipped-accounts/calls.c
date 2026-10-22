/* SPDX-License-Identifier: 0BSD */
/* Copyright (c) 2026 Bjorn Pagen */
/* An object that calls each entry of the account of what a call holds, and
 * nothing else: the names this target's object format gives the three, as
 * a reference reads, and the reader shown to find a reference where there
 * is one. */
#include "idris_rt.h"

void account(void) {
  idris_rt_peak_enter((const idris_rt_text *)0, 16);
  idris_rt_peak_held(16);
  idris_rt_peak_leave();
}
