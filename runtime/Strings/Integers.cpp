// The decimal text of integers.
// PIN(runtime-quarantine) — see PINS.md
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stdint.h>

namespace rt::strings {

char *formatUnsigned(uint64_t value, char *end) {
  do {
    *--end = static_cast<char>('0' + value % 10);
    value /= 10;
  } while (value != 0);
  return end;
}

char *formatSigned(int64_t value, char *end) {
  uint64_t magnitude = value < 0 ? 0 - static_cast<uint64_t>(value) : static_cast<uint64_t>(value);
  char *start = formatUnsigned(magnitude, end);
  if (value < 0)
    *--start = '-';
  return start;
}

} // namespace rt::strings

extern "C" int32_t idris_rt_int_head_s(int64_t value) {
  char text[rt::strings::intTextMax];
  return *rt::strings::formatSigned(value, text + sizeof text);
}

extern "C" int32_t idris_rt_int_head_u(uint64_t value) {
  char text[rt::strings::intTextMax];
  return *rt::strings::formatUnsigned(value, text + sizeof text);
}
