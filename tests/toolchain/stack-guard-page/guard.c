/* The reserved-stack runner, idris_rt_run_on_stack, asked for a stack and a
 * guard that are not whole pages of the build's page size (TEST_PAGE_SIZE):
 * a recursion that keeps every frame runs into the guard, which ends it as
 * exhaustion, from the fault handler on its own stack (SIGBUS on Darwin,
 * SIGSEGV on Linux). The handler measures how deep the stack went and
 * exits 10 when that is what the runner promises (at least the stack asked
 * for, and no more than it rounded up to whole pages), 11 when not. The mode
 * is argv[1]: "rounded" asks for three pages and a byte with a one-byte
 * guard, "no-guard" for the same with a guard of 0 bytes, "tiny" for one
 * byte of stack. */
#include "idris_rt.h"

#include <stdint.h>
#include <string.h>
#include <unistd.h>

static const size_t page = TEST_PAGE_SIZE;
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

int main(int argc, char **argv) {
  const char *mode = argc > 1 ? argv[1] : "";
  size_t guard = 1;
  most = 3 * page + 1;
  if (strcmp(mode, "no-guard") == 0)
    guard = 0;
  else if (strcmp(mode, "tiny") == 0)
    most = 1;
  if (idris_rt_run_on_stack(run, NULL, most, guard, exhausted) != 0)
    return 12;
  return 13;
}
