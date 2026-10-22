// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* A call's frame bound, as the checked runtime holds it (Alloc/Peaks.cpp):
 * the compiled program says where an activation begins, with the bound the
 * compiler computed for its function, each change of what it holds that it
 * no longer needs, and where it ends; a cell made while a call holds more
 * than its bound ends the run with the ending FrameBoundExceeded. Here the
 * program makes the calls the lowering would, in one of four modes:
 *
 *     within   holds up to its bound while a cell is made
 *     idle     holds past its bound while no cell is made
 *     over     holds past its bound while a cell is made
 *     callee   holds past its bound while a call it made makes a cell
 *
 * Every cell it makes it frees, and it counts no cell twice, so the bound is
 * the one internal error it can reach. */
#include <string.h>

#include "idris_rt.h"
#include "program.h"

static const char *mode = "";

/* The functions' names, laid out as idris_rt_text: the static texts of the
 * program the lowering writes. */
static const struct {
  uint32_t length;
  char bytes[8];
} caller = {6, "caller"}, callee = {6, "callee"};

/* A cell made and freed: an allocation while the innermost activation
 * holds what it holds. */
static void allocate(void) {
  idris_rt_header *cell = idris_rt_cell(16, idris_rt_info(0, 0, IDRIS_RT_KIND_BOX));
  idris_rt_dec_cell(cell);
}

static void body(void) {
  int64_t bound = strcmp(mode, "within") == 0 ? 32 : 16;
  idris_rt_peak_enter((const idris_rt_text *)(const void *)&caller, bound);
  idris_rt_peak_held(32);
  if (strcmp(mode, "callee") == 0) {
    idris_rt_peak_enter((const idris_rt_text *)(const void *)&callee, 0);
    allocate();
    idris_rt_peak_leave();
  } else if (strcmp(mode, "idle") != 0) {
    allocate();
  }
  idris_rt_peak_held(-32);
  idris_rt_peak_leave();
}

IDRIS_RT_TEST_PROGRAM("frame-bound", 256 * 1024);

int main(int argc, char **argv) {
  mode = argc > 1 ? argv[1] : "";
  idris_rt_test_start(body, argc, argv);
}
