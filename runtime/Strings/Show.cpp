// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The decimal text of an integer: as a string, and its first character.
// PIN(runtime-quarantine) — see PINS.md
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

extern "C" const idris_rt_str *idris_rt_str_show_s(int64_t value) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::strings::formatSigned(value, end);
  return rt::strings::asciiOf(start, static_cast<size_t>(end - start));
}

extern "C" const idris_rt_str *idris_rt_str_show_u(uint64_t value) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::strings::formatUnsigned(value, end);
  return rt::strings::asciiOf(start, static_cast<size_t>(end - start));
}

extern "C" int32_t idris_rt_int_head_s(int64_t value) {
  char text[rt::strings::intTextMax];
  return *rt::strings::formatSigned(value, text + sizeof text);
}

extern "C" int32_t idris_rt_int_head_u(uint64_t value) {
  char text[rt::strings::intTextMax];
  return *rt::strings::formatUnsigned(value, text + sizeof text);
}
