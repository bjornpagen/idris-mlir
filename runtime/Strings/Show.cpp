// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The decimal text of an integer: as a string, written to standard output
// with no string, and its first character.
// PIN(runtime-quarantine) — see PINS.md
#include "Io/Io.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <concepts>
#include <stddef.h>
#include <stdint.h>

namespace {

// The decimal text of a signed or an unsigned integer, formatted on the
// stack and handed to `take`: the show makes a string of it, the writer
// writes it to standard output, so both write the one text.
template <class Value, std::invocable<const char *, size_t> Take>
auto withText(Value value, Take take) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = [&] {
    if constexpr (std::same_as<Value, int64_t>)
      return rt::strings::formatSigned(value, end);
    else
      return rt::strings::formatUnsigned(value, end);
  }();
  return take(start, static_cast<size_t>(end - start));
}

} // namespace

// The decimal text of a signed or an unsigned integer, a new string.
extern "C" const idris_rt_str *idris_rt_str_show_s(int64_t value) {
  return withText(value, rt::strings::asciiOf);
}

extern "C" const idris_rt_str *idris_rt_str_show_u(uint64_t value) {
  return withText(value, rt::strings::asciiOf);
}

// The same text, written to standard output.
extern "C" void idris_rt_io_put_s(int64_t value) { withText(value, rt::io::putOutput); }

extern "C" void idris_rt_io_put_u(uint64_t value) { withText(value, rt::io::putOutput); }

// The first character of the decimal text of a signed or an unsigned
// integer.
extern "C" int32_t idris_rt_int_head_s(int64_t value) {
  char text[rt::strings::intTextMax];
  return *rt::strings::formatSigned(value, text + sizeof text);
}

extern "C" int32_t idris_rt_int_head_u(uint64_t value) {
  char text[rt::strings::intTextMax];
  return *rt::strings::formatUnsigned(value, text + sizeof text);
}
