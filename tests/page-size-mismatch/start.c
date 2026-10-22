// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* A program as @main is: idris_rt_start with the record of a body that
 * writes one line. Whether the line reaches stdout says whether the program
 * ran at all. */
#include "idris_rt.h"
#include "program.h"

static void body(void) {
  idris_rt_io_put_char('r');
  idris_rt_io_put_char('a');
  idris_rt_io_put_char('n');
  idris_rt_io_put_char('\n');
}

/* A few frames of its own. */
IDRIS_RT_TEST_PROGRAM("start", 64 * 1024);

int main(int argc, char **argv) { idris_rt_test_start(body, argc, argv); }
