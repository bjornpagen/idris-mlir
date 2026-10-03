// rt.strings:show: the text of an integer as a string.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

export module rt.strings:show;

import :integers;
import :making;

extern "C" const idris_rt_str *idris_rt_str_show_s(int64_t value) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::strings::formatSigned(value, end);
  return rt::strings::stringOf(start, static_cast<size_t>(end - start));
}

extern "C" const idris_rt_str *idris_rt_str_show_u(uint64_t value) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::strings::formatUnsigned(value, end);
  return rt::strings::stringOf(start, static_cast<size_t>(end - start));
}
