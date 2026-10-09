// rt.io:lines: the text base reads from and writes to a handle
// (System.File.ReadWrite): lines, characters and strings. Standard input is
// read through its buffer, which getLine reads too, so the two interleave on
// one input without losing a byte; standard output and error are written as
// putStr writes them, in order with it.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

export module rt.io:lines;

import rt.platform;
import :bytes;
import :errors;
import :handles;
import :input;
import :scratch;
import :writing;

namespace {

// Where text is read from: standard input's buffer, or a file's stream.
struct Source {
  rt::platform::File *file;

  // The next byte, consumed, or -1 at the end or when the read failed.
  int32_t next() {
    if (file != nullptr)
      return rt::platform::readByte(file);
    int32_t b = rt::io::peek();
    if (b >= 0)
      ++rt::io::inputPosition;
    return b;
  }

  // Whether a read of the stream has failed, as ferror says. A file's
  // failure is saved here; standard input's, by the read that failed.
  bool failed() {
    if (file == nullptr)
      return rt::io::inputFailed;
    if (!rt::platform::fileFailed(file))
      return false;
    rt::io::saveError();
    return true;
  }
};

// The source of a handle; false when it is no stream to read from (EBADF).
bool sourceOf(int64_t handle, Source &source) {
  source.file = nullptr;
  if (handle == 0)
    return true;
  source.file = rt::io::fileOf(handle);
  return source.file != nullptr;
}

// A string handle of the program's, holding the bytes decoded as any bytes
// from outside the program are.
int64_t programString(const rt::io::Scratch &bytes) {
  return rt::io::newString(idris_rt_str_from_bytes(bytes.bytes, bytes.length));
}

} // namespace

// The next line of a file, through its '\n' when it has one, as a string
// handle the program owns: as POSIX's getline reads it. At the end of the
// file it is the empty string; it is null when a read failed before any
// byte of the line, or the handle is no stream to read from.
extern "C" int64_t idris_rt_io_file_read_line(int64_t file) {
  Source source{};
  if (!sourceOf(file, source))
    return rt::io::nullHandle;
  rt::io::Scratch line;
  int32_t b = source.next();
  for (; b >= 0; b = source.next()) {
    line.push(static_cast<char>(b));
    if (b == '\n')
      break;
  }
  if (b < 0 && source.failed() && line.length == 0)
    return rt::io::nullHandle;
  return programString(line);
}

// Up to `max` bytes of a file, fewer only at its end, as a string handle the
// program owns, as fread reads them. A character cut at the end is decoded
// as any bytes from outside are. Null when nothing was read: at the end, for
// a `max` of 0 or less, on a failure, or when the handle is no stream to read
// from.
extern "C" int64_t idris_rt_io_file_read_chars(int64_t max, int64_t file) {
  rt::io::Scratch chars;
  while (static_cast<int64_t>(chars.length) < max) {
    auto left = static_cast<size_t>(max - static_cast<int64_t>(chars.length));
    size_t wanted = left < rt::io::bufferSize ? left : rt::io::bufferSize;
    chars.reserve(wanted);
    int64_t got = rt::io::readBytes(file, chars.bytes + chars.length, wanted);
    if (got <= 0)
      break;
    chars.length += static_cast<size_t>(got);
    if (static_cast<size_t>(got) < wanted)
      break;
  }
  if (chars.length == 0)
    return rt::io::nullHandle;
  return programString(chars);
}

// fgetc's: the next byte of a file, 0 to 255, or -1 at its end, on a failure,
// or when the handle is no stream to read from.
extern "C" int64_t idris_rt_io_file_read_char(int64_t file) {
  Source source{};
  if (!sourceOf(file, source))
    return -1;
  int32_t b = source.next();
  if (b < 0)
    source.failed();
  return b;
}

// Skips a file through its next '\n': 0, also at its end; -1 when a read
// failed or the handle is no stream to read from.
extern "C" int64_t idris_rt_io_file_seek_line(int64_t file) {
  Source source{};
  if (!sourceOf(file, source))
    return -1;
  int32_t b = source.next();
  while (b >= 0 && b != '\n')
    b = source.next();
  return b < 0 && source.failed() ? -1 : 0;
}

// Writes all of a string's bytes to a file, as fPutStr asks: 1 when they were
// written, 0 when the write failed or the handle is no stream to write to.
extern "C" int64_t idris_rt_io_file_write_line(int64_t file, const idris_rt_str *line) {
  int64_t n = idris_rt_str_bytes_length(line);
  return rt::io::writeBytes(file, idris_rt_str_bytes(line), static_cast<size_t>(n)) == n ? 1 : 0;
}
