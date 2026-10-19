// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The checked runtime on cells built by hand as idr-lower lays them out:
 * each mode makes one misuse of a count, which ends the program naming it,
 * or none.
 *
 *   checked held      a box holding a string, a stack cell holding a box,
 *                     each counted as it must be; then idris_rt_main_return
 *   checked twice     a box released twice
 *   checked holder    a string released while a box still holds it, then
 *                     the box released
 *   checked dead      a stack cell released to its end, then counted again
 *   checked returned  a stack cell counted after its frame returned */
#include <stdint.h>
#include <string.h>

#include "idris_rt.h"

/* A box of one object slot. */
static void *box(void *field) {
  void **cell = idris_rt_cell(16, idris_rt_info(0, 1, IDRIS_RT_KIND_BOX));
  cell[1] = field;
  return cell;
}

static const idris_rt_str *text(const char *s) { return idris_rt_str_from_utf8(s, strlen(s)); }

/* A stack cell as idr-lower writes one into its frame's slot: a box of one
 * object slot with the stack mark. */
struct stack_box {
  idris_rt_header header;
  void *field;
};

static void stack_box(struct stack_box *cell, void *field) {
  cell->header.count = 1;
  cell->header.info = idris_rt_info(0, 1, IDRIS_RT_KIND_BOX) | IDRIS_RT_STACK_CELL;
  cell->field = field;
}

static void held(void) {
  void *b = box((void *)text("held"));
  idris_rt_inc(b);
  idris_rt_dec(b);
  struct stack_box s;
  stack_box(&s, b);
  idris_rt_inc(&s);
  idris_rt_dec(&s);
  idris_rt_dec(&s);
}

static void twice(void) {
  void *b = box(NULL);
  idris_rt_dec(b);
  idris_rt_dec(b);
}

static void holder(void) {
  const idris_rt_str *s = text("held");
  void *b = box((void *)s);
  idris_rt_dec((void *)s);
  idris_rt_dec(b);
}

static void dead(void) {
  struct stack_box s;
  stack_box(&s, NULL);
  idris_rt_dec(&s);
  idris_rt_inc(&s);
}

/* A stack cell of a frame that returns, kept past it: volatile, so that the
 * store is made and the cell is written as the frame's. The frame holds
 * more cells, and the one kept is the lowest, so that it lies below the
 * frames of the calls the count makes after the return. */
static struct stack_box *volatile kept;

__attribute__((noinline)) static void keep(void) {
  struct stack_box cells[16];
  for (int i = 0; i < 16; ++i)
    stack_box(&cells[i], NULL);
  kept = &cells[0];
}

static void returned(void) {
  keep();
  idris_rt_inc(kept);
}

int main(int argc, char **argv) {
  const char *mode = argc > 1 ? argv[1] : "";
  if (strcmp(mode, "held") == 0)
    held();
  else if (strcmp(mode, "twice") == 0)
    twice();
  else if (strcmp(mode, "holder") == 0)
    holder();
  else if (strcmp(mode, "dead") == 0)
    dead();
  else if (strcmp(mode, "returned") == 0)
    returned();
  else
    return 2;
  idris_rt_main_return();
  return 0;
}
