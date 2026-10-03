// rt.io:bytes: writing and reading a range of a byte array.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

export module rt.io:bytes;

import :input;
import :output;
import :writing;

namespace {

// The bytes [offset, offset + count) of a byte array, or a crash.
char *byteRange(idris_rt_array *bytes, int64_t length, int64_t offset, int64_t count) {
  if (offset < 0 || count < 0 || offset > length || count > length - offset) {
    static constexpr char message[] = "idris-mlir: a byte range outside the buffer\n";
    idris_rt_crash(message, sizeof message - 1);
  }
  return reinterpret_cast<char *>(bytes + 1) + offset;
}

} // namespace

extern "C" int64_t idris_rt_io_write_bytes(int64_t handle, idris_rt_array *bytes, int64_t length,
                                           int64_t offset, int64_t count) {
  const char *p = byteRange(bytes, length, offset, count);
  auto n = static_cast<size_t>(count);
  if (handle == 1) {
    rt::io::putBytes(p, n);
  } else if (handle == 2) {
    idris_rt_flush();
    rt::io::writeAll(2, p, n);
  } else {
    return 0;
  }
  return count;
}

extern "C" int64_t idris_rt_io_read_bytes(int64_t handle, idris_rt_array *bytes, int64_t length,
                                          int64_t offset, int64_t count) {
  using namespace rt::io;
  char *p = byteRange(bytes, length, offset, count);
  if (handle != 0)
    return 0;
  int64_t got = 0;
  while (got < count && peek() >= 0) {
    size_t available = inputLength - inputPosition;
    auto wanted = static_cast<size_t>(count - got);
    size_t step = available < wanted ? available : wanted;
    volatile char *to = p + got;
    for (size_t i = 0; i < step; ++i)
      to[i] = input[inputPosition + i];
    inputPosition += step;
    got += static_cast<int64_t>(step);
  }
  return got;
}
