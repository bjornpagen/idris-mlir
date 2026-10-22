// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The runtime's entry, idris_rt_start, as a program's @main calls it, with
 * the record of what the lowering knows of the program; the argument picks
 * what the body does, or what the program requires of the processor, and
 * the test reads the exit status, stdout and stderr. Every body writes
 * buffered output first, which must reach stdout however it ends.
 *
 *   million        a recursion a million frames deep, on the stack the
 *                  program states, far deeper than the process's own
 *   exit-0         exit 0
 *   exit-255       exit 255
 *   crash          a crash of a cause of the closed set, at a site
 *   said           a crash of a trusted library's text, at a site
 *   unreportable   an exit of 300, which no parent can read, at a site
 *   memory         running out of memory
 *   cpu, cpu-two   a processor that lacks one or two features the program
 *                  requires: refused before the body runs, and named */
#include "idris_rt.h"

#include <stdint.h>
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

/* A site's texts, laid out as idris_rt_text: the static texts of the
 * program the lowering writes, one per file and per function. */
static const struct {
  uint32_t length;
  char bytes[16];
} file = {8, "Main.idr"}, function = {9, "Main.main"};

static void crashAt(int32_t cause) {
  idris_rt_crash_at(cause, (void *)&function, (void *)&file, 3, 7);
}

static void body(void) {
  idris_rt_io_put_char('4');
  idris_rt_io_put_char('2');
  idris_rt_io_put_char('\n');
  if (strcmp(mode, "million") == 0) {
    if (deep(1000000) != INT64_C(500000500000))
      idris_rt_exit(1);
  } else if (strcmp(mode, "exit-0") == 0) {
    idris_rt_exit(0);
  } else if (strcmp(mode, "exit-255") == 0) {
    idris_rt_exit(255);
  } else if (strcmp(mode, "crash") == 0) {
    /* The first cause of the specification's list, division by zero. */
    crashAt(0);
  } else if (strcmp(mode, "said") == 0) {
    idris_rt_crash_message_at(idris_rt_str_from_utf8("the text given", 14), (void *)&function,
                              (void *)&file, 3, 7);
  } else if (strcmp(mode, "unreportable") == 0) {
    idris_rt_unreportable_at(300, (void *)&function, (void *)&file, 3, 7);
  } else if (strcmp(mode, "memory") == 0) {
    idris_rt_out_of_memory();
  }
}

/* The million frames of `deep`, a few words each on every target, with
 * room to spare; the process's own stack, which the run script makes
 * small, would not hold them. */
const idris_rt_built idris_rt_program_built = {UINT64_C(64) << 20, 0, 0, "start", 5};

int main(int argc, char **argv) {
  static idris_rt_program program;
  program.body = body;
  if (argc > 1)
    mode = argv[1];
  /* A bit no feature of either target's list names, which the entry's
   * test of the processor never finds: it refuses to run the program and
   * names the bit by its number. */
  if (strcmp(mode, "cpu") == 0)
    program.cpu_features = UINT64_C(1) << 63;
  /* Two such bits, each named. */
  if (strcmp(mode, "cpu-two") == 0)
    program.cpu_features = UINT64_C(1) << 61 | UINT64_C(1) << 63;
  idris_rt_start(&program, argc, argv);
}
