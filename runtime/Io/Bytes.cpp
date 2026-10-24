// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Writing and reading bytes on a handle: a range of a byte array
// (Data.Buffer's transfers), and the text base writes and reads.
#include "Io/Io.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace rt::io {

size_t writeBytes(int64_t handle, const char *p, size_t n) {
  return withStream(handle, [&](const Stream auto &stream) { return stream.write(p, n).count; });
}

size_t readBytes(int64_t handle, char *p, size_t n) {
  return withStream(handle, [&](const Stream auto &stream) { return stream.read(p, n); });
}

} // namespace rt::io

// Writes the bytes [offset, offset + count) of a byte array to a handle's
// stream, in order with every other write to it: standard output through its
// buffer, standard error after what standard output has pending, a file
// through its stream. Gives the count written: fewer when the write failed,
// and 0 when the handle is no stream to write to.
extern "C" int64_t idris_rt_io_write_bytes(int64_t handle, idris_rt_array *buffer, int64_t offset,
                                           int64_t count) {
  char *bytes = idris_rt_array_bytes(buffer) + offset;
  return static_cast<int64_t>(rt::io::writeBytes(handle, bytes, static_cast<size_t>(count)));
}

// Reads bytes from a handle's stream into [offset, offset + count) of a byte
// array, waiting until that many or the end of its input: standard input
// through the buffer idris_rt_io_get_line reads too, a file through its
// stream. Gives the count read: fewer at the end of input or when the read
// failed, and 0 when the handle is no stream to read from.
extern "C" int64_t idris_rt_io_read_bytes(int64_t handle, idris_rt_array *buffer, int64_t offset,
                                          int64_t count) {
  char *bytes = idris_rt_array_bytes(buffer) + offset;
  return static_cast<int64_t>(rt::io::readBytes(handle, bytes, static_cast<size_t>(count)));
}
