/* A program as @main is: idris_rt_start with a body that writes one line.
 * Whether the line reaches stdout says whether the program ran at all. */
#include "idris_rt.h"

static int64_t body(void) {
  idris_rt_io_put_char('r');
  idris_rt_io_put_char('a');
  idris_rt_io_put_char('n');
  idris_rt_io_put_char('\n');
  return 0;
}

int main(void) {
  int32_t status = idris_rt_start(body, 0);
  idris_rt_flush();
  return status;
}
