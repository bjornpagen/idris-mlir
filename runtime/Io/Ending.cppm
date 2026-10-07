// rt.io:ending: how a program ends: returning from main, or a crash.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdlib.h>
#include <unistd.h>

export module rt.io:ending;

import rt.alloc;
import rt.strings;
import :writing;

namespace {

// The live cells on standard error when IDRIS_RT_LIVE is "1", in one write:
// how a test sees that a program frees every cell it allocates. An
// evaluation child counts nothing, and its standard error is the compiler's.
void reportLiveCells() {
  if (rt::alloc::arenaActive)
    return;
  const char *setting = getenv("IDRIS_RT_LIVE");
  if (setting == nullptr || setting[0] != '1' || setting[1] != '\0')
    return;
  static constexpr char prefix[] = "idris-rt: live cells ";
  constexpr size_t prefixLength = sizeof prefix - 1;
  char line[prefixLength + rt::strings::intTextMax + 1];
  char *end = line + sizeof line;
  end[-1] = '\n';
  char *start = rt::strings::formatUnsigned(idris_rt_live_cells(), end - 1) - prefixLength;
  rt::io::copyOut(start, prefix, prefixLength);
  rt::io::writeAll(2, start, static_cast<size_t>(end - start));
}

} // namespace

extern "C" void idris_rt_main_return(void) {
  idris_rt_flush();
  reportLiveCells();
}

extern "C" void idris_rt_crash(const char *msg, size_t len) {
  idris_rt_flush();
  rt::io::writeAll(2, msg, len);
  _exit(IDRIS_RT_CRASHED);
}
