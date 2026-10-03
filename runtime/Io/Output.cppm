// rt.io:output: standard output, through a buffer that a flush writes.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

export module rt.io:output;

import rt.doubles;
import rt.strings;
import :writing;

namespace {

using rt::io::bufferSize;

// Written through a volatile pointer, so that LLVM makes no memcpy of the
// copy loop.
char output[bufferSize];
size_t outputLength = 0;

} // namespace

namespace rt::io {

void putBytes(const char *p, size_t n) {
  if (outputLength + n > bufferSize)
    idris_rt_flush();
  if (n > bufferSize) {
    writeAll(1, p, n);
    return;
  }
  volatile char *to = output + outputLength;
  for (size_t i = 0; i < n; ++i)
    to[i] = p[i];
  outputLength += n;
}

} // namespace rt::io

extern "C" void idris_rt_flush(void) {
  rt::io::writeAll(1, output, outputLength);
  outputLength = 0;
}

extern "C" void idris_rt_io_put_str(const idris_rt_str *s) {
  rt::io::putBytes(idris_rt_str_bytes(s), s->bytes);
}

extern "C" void idris_rt_io_put_char(int32_t c) {
  char bytes[4];
  rt::io::putBytes(bytes, rt::strings::encodeUtf8(c, bytes));
}

extern "C" void idris_rt_io_put_int_s(int64_t value) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::strings::formatSigned(value, end);
  rt::io::putBytes(start, static_cast<size_t>(end - start));
}

extern "C" void idris_rt_io_put_int_u(uint64_t value) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::strings::formatUnsigned(value, end);
  rt::io::putBytes(start, static_cast<size_t>(end - start));
}

extern "C" void idris_rt_io_put_double(double value) {
  char text[rt::doubles::doubleTextMax];
  rt::io::putBytes(text, rt::doubles::formatDouble(value, text));
}
