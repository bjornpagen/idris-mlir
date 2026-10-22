// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The checked runtime on cells built by hand as idr-lower lays them out,
 * run as a program: each mode makes one misuse of a count, which ends the
 * program as the runtime's internal error naming it, or none.
 *
 *   checked held     a box holding a string, counted as it must be, and
 *                    released: the program returns
 *   checked twice    a box released twice
 *   checked holder   a string released while a box still holds it, then
 *                    the box released
 *   checked leak     a box left held when the body returns */
#include <stdint.h>
#include <string.h>

#include "idris_rt.h"
#include "program.h"

/* A box of one object slot. */
static void *box(void *field) {
  void **cell = (void **)idris_rt_cell(16, idris_rt_info(0, 1, IDRIS_RT_KIND_BOX));
  cell[1] = field;
  return cell;
}

static void *text(const char *s) { return (void *)idris_rt_str_from_utf8(s, strlen(s)); }

static void held(void) {
  void *b = box(text("held"));
  idris_rt_inc_cell(b);
  idris_rt_dec_cell(b);
  idris_rt_dec_cell(b);
}

static void twice(void) {
  void *b = box(NULL);
  idris_rt_dec_cell(b);
  idris_rt_dec_cell(b);
}

static void holder(void) {
  void *s = text("held");
  void *b = box(s);
  idris_rt_dec_cell(s);
  idris_rt_dec_cell(b);
}

static void leak(void) { (void)box(NULL); }

static const char *mode = "";

static void body(void) {
  if (strcmp(mode, "held") == 0)
    held();
  else if (strcmp(mode, "twice") == 0)
    twice();
  else if (strcmp(mode, "holder") == 0)
    holder();
  else if (strcmp(mode, "leak") == 0)
    leak();
}

/* A few frames of its own. */
IDRIS_RT_TEST_PROGRAM("checked", 64 * 1024);

int main(int argc, char **argv) {
  mode = argc > 1 ? argv[1] : "";
  idris_rt_test_start(body, argc, argv);
}
