/* The runtime's entry, idris_rt_start, as a program's @main calls it: the
 * argument picks the program, the processor requirement and what body
 * returns, and the test reads the exit status, stdout and stderr. */
#include "idris_rt.h"

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

static int64_t body(void) {
  /* Buffered output, which must reach stdout however body ends. */
  idris_rt_io_put_int_s(42);
  idris_rt_io_put_char('\n');
  if (strcmp(mode, "deep") == 0)
    return deep(INT64_C(1) << 40) == 0;
  if (strcmp(mode, "million") == 0)
    return deep(1000000) == INT64_C(500000500000) ? 0 : 1;
  if (strcmp(mode, "255") == 0)
    return 255;
  if (strcmp(mode, "256") == 0)
    return 256;
  if (strcmp(mode, "negative") == 0)
    return -1;
  return 0;
}

int main(int argc, char **argv) {
  uint64_t required = 0;
  if (argc > 1)
    mode = argv[1];
  /* A feature no processor has: the entry refuses to run the program. */
  if (strcmp(mode, "cpu") == 0)
    required = UINT64_C(1) << 63;
  int32_t status = idris_rt_start(body, required, argc, argv);
  idris_rt_flush();
  return status;
}
