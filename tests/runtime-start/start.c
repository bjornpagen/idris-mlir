// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The runtime's entry, idris_rt_start, as a program's @main calls it: the
 * argument picks the program (deep, million, hoard), the processor requirement
 * (cpu, cpu-two) or, as a decimal number, the value body returns, and the
 * test reads the exit status, stdout and stderr. */
#include "idris_rt.h"

#include <stdlib.h>
#include <string.h>

static const char *mode = "";

/* As deep as it is asked to go, keeping every frame, since each call adds
 * to the result of the next. */
static int64_t deep(int64_t n) {
  if (n == 0)
    return 0;
  volatile int64_t keep = n;
  return deep(n - 1) + keep;
}

/* Cells, each holding the one before, so that none is ever free: a
 * program that runs away. Only the heap's end stops it. */
static int64_t hoard(void) {
  void *held = NULL;
  for (;;) {
    void **cell = idris_rt_cell(3 * sizeof(void *), 0);
    cell[1] = held;
    held = cell;
  }
}

static int64_t body(void) {
  /* Buffered output, which must reach stdout however body ends. */
  idris_rt_io_put_int_s(42);
  idris_rt_io_put_char('\n');
  if (strcmp(mode, "deep") == 0)
    return deep(INT64_C(1) << 40) == 0;
  if (strcmp(mode, "hoard") == 0)
    return hoard();
  if (strcmp(mode, "million") == 0)
    return deep(1000000) == INT64_C(500000500000) ? 0 : 1;
  /* Any other mode is the decimal value body returns. */
  return strtoll(mode, NULL, 10);
}

int main(int argc, char **argv) {
  uint64_t required = 0;
  if (argc > 1)
    mode = argv[1];
  /* A bit no feature of either target's list names, which the entry's
   * test of the processor never finds: it refuses to run the program and
   * names the bit by its number. */
  if (strcmp(mode, "cpu") == 0)
    required = UINT64_C(1) << 63;
  /* Two such bits, each named. */
  if (strcmp(mode, "cpu-two") == 0)
    required = UINT64_C(1) << 61 | UINT64_C(1) << 63;
  int32_t status = idris_rt_start(body, required, argc, argv);
  idris_rt_flush();
  return status;
}
