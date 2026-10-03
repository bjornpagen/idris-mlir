// rt.strings:integers: the decimal text of integers.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

export module rt.strings:integers;

export namespace rt::strings {

inline constexpr size_t intTextMax = 20;

// The decimal digits of an integer, written backwards from `end`; returns
// where they start.
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
