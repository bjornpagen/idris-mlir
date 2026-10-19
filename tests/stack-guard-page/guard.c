// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The reserved-stack runner, idris_rt_run_on_stack, asked for a stack and a
 * guard that are not whole pages of the build's page size (TEST_PAGE_SIZE):
 * a recursion that keeps every frame runs into the guard, which ends it as
 * exhaustion, from the fault handler on its own stack (SIGBUS on Darwin,
 * SIGSEGV on Linux). The handler measures how deep the stack went and
 * exits 10 when that is what the runner promises (at least the stack asked
 * for, and no more than it rounded up to whole pages), 11 when not. The mode
 * is argv[1] (modes, below): stacks just past whole pages, of whole pages
 * and just under them, and of one byte, with guards of 0, 1 and a page and
 * a byte; and two planted modes, judged by a stack other than the one
 * asked for, where the judgement must fail. */
#include "idris_rt.h"

#include <stdint.h>
#include <string.h>
#include <unistd.h>

static const size_t page = TEST_PAGE_SIZE;
/* The stack the handler judges the runner by: the one asked for, but in a
 * planted mode, which judges by another, so that the judgement is shown
 * failing. */
static size_t most;
static volatile uintptr_t top;
static volatile uintptr_t lowest;

static int64_t deep(int64_t n) {
  volatile int64_t frame[4] = {n, n, n, n};
  uintptr_t here = (uintptr_t)frame;
  if (here < lowest)
    lowest = here;
  return deep(n + 1) + frame[0];
}

static void run(void *argument) {
  (void)argument;
  volatile char mark = 0;
  top = (uintptr_t)&mark;
  lowest = top;
  deep(mark);
}

/* On the signal stack: only arithmetic and _exit. The frames above the
 * first one (the thread's start) and the last frame are less than half a
 * page on every system the runtime runs on. */
static void exhausted(void) {
  size_t rounded = (most + page - 1) / page * page;
  size_t used = (size_t)(top - lowest);
  int asked = used + page / 2 >= most;
  int within = used <= rounded;
  _exit(asked && within ? 10 : 11);
}

/* A mode: the stack and guard asked for, and the stack judged by. */
struct mode {
  const char *name;
  size_t stack, guard, judged;
};

int main(int argc, char **argv) {
  const char *name = argc > 1 ? argv[1] : "";
  const struct mode modes[] = {
      /* Three pages and a byte, with a guard of a byte, of none, and of a
       * page and a byte, two pages. */
      {"rounded", 3 * page + 1, 1, 3 * page + 1},
      {"no-guard", 3 * page + 1, 0, 3 * page + 1},
      {"wide-guard", 3 * page + 1, page + 1, 3 * page + 1},
      /* Whole pages, which round to themselves, and a byte under them. */
      {"whole", 4 * page, 1, 4 * page},
      {"below", 4 * page - 1, 1, 4 * page - 1},
      {"tiny", 1, 1, 1},
      /* Judged by twice the stack asked for, which it cannot reach, and by
       * one page, which it goes past: each must exit 11. */
      {"planted-short", 3 * page + 1, 1, 6 * page + 2},
      {"planted-long", 3 * page + 1, 1, page},
  };
  for (size_t i = 0; i < sizeof modes / sizeof modes[0]; ++i) {
    if (strcmp(name, modes[i].name) != 0)
      continue;
    most = modes[i].judged;
    if (idris_rt_run_on_stack(run, NULL, modes[i].stack, modes[i].guard, exhausted) != 0)
      return 12;
    return 13;
  }
  return 2;
}
