// rt.io:bytes: writing and reading bytes on a handle: a range of a byte
// array (Data.Buffer's transfers), and the text base writes and reads.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

export module rt.io:bytes;

import rt.platform;
import :errors;
import :handles;
import :input;
import :output;
import :writing;

namespace rt::io {

// The n bytes at p to a handle, in order with every other write to it:
// standard output through its buffer, standard error after what standard
// output has pending, a file through its stream. Gives the count written,
// fewer when the write failed (errno saved), or -1 when the handle is no
// stream to write to (EBADF).
int64_t writeBytes(int64_t handle, const char *p, size_t n) {
  if (handle == 1) {
    putBytes(p, n);
    return static_cast<int64_t>(n);
  }
  if (handle == 2) {
    idris_rt_flush();
    writeAll(2, p, n);
    return static_cast<int64_t>(n);
  }
  rt::platform::File *file = fileOf(handle);
  if (file == nullptr)
    return -1;
  size_t written = rt::platform::writeFile(file, p, n);
  if (written < n)
    saveError();
  return static_cast<int64_t>(written);
}

// Up to n bytes from a handle into p: standard input through its buffer, a
// file through its stream, waiting until n bytes or the end. Gives the count
// read, fewer at the end or when the read failed (errno saved), or -1 when the
// handle is no stream to read from (EBADF).
int64_t readBytes(int64_t handle, char *p, size_t n) {
  if (handle == 0)
    return static_cast<int64_t>(readInput(p, n));
  rt::platform::File *file = fileOf(handle);
  if (file == nullptr)
    return -1;
  size_t got = rt::platform::readFile(file, p, n);
  if (got < n && rt::platform::fileFailed(file))
    saveError();
  return static_cast<int64_t>(got);
}

} // namespace rt::io

extern "C" int64_t idris_rt_io_write_bytes(int64_t handle, idris_rt_array *bytes, int64_t length,
                                           int64_t offset, int64_t count) {
  const char *p = idris_rt_buffer_at(bytes, length, offset, count);
  int64_t written = rt::io::writeBytes(handle, p, static_cast<size_t>(count));
  return written < 0 ? 0 : written;
}

extern "C" int64_t idris_rt_io_read_bytes(int64_t handle, idris_rt_array *bytes, int64_t length,
                                          int64_t offset, int64_t count) {
  char *p = idris_rt_buffer_at(bytes, length, offset, count);
  int64_t got = rt::io::readBytes(handle, p, static_cast<size_t>(count));
  return got < 0 ? 0 : got;
}
