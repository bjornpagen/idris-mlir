// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The text base reads from and writes to a handle (System.File.ReadWrite):
// lines, characters and strings, each through the handle's stream, so that
// standard input is read through its buffer, which getLine reads too, and
// standard output and error are written as putStr writes them, in order
// with it.
// PIN(runtime-quarantine) — see PINS.md
#include "Io/Io.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace {

using Got = rt::io::ByteRead::Got;

// A string handle of the program's, holding the bytes decoded as any bytes
// from outside the program are.
int64_t programString(const rt::io::Scratch &bytes) {
  return rt::io::newString(idris_rt_str_from_bytes(bytes.bytes, bytes.length));
}

} // namespace

// The next line of a stream, through its '\n' when it has one, as a string
// handle the program owns: as POSIX's getline reads it. At the end of the
// stream it is the empty string; it is null when a read failed before any
// byte of the line, or the handle is no stream to read from.
extern "C" int64_t idris_rt_io_file_read_line(int64_t file) {
  return rt::io::withStream(file, [](const rt::io::Stream auto &stream) -> int64_t {
    rt::io::Scratch line;
    rt::io::ByteRead read = stream.readByte();
    for (; read.got == Got::Byte; read = stream.readByte()) {
      line.push(static_cast<char>(read.byte));
      if (read.byte == '\n')
        break;
    }
    if (read.got == Got::Failure && line.length == 0)
      return rt::io::nullHandle;
    return programString(line);
  });
}

// Up to `max` bytes of a stream, fewer only at its end, as a string handle
// the program owns, as fread reads them. A character cut at the end is
// decoded as any bytes from outside are. Null when nothing was read: at the
// end, for a `max` of 0 or less, on a failure, or when the handle is no
// stream to read from.
extern "C" int64_t idris_rt_io_file_read_chars(int64_t max, int64_t file) {
  rt::io::Scratch chars;
  while (static_cast<int64_t>(chars.length) < max) {
    auto left = static_cast<size_t>(max - static_cast<int64_t>(chars.length));
    size_t wanted = left < rt::io::bufferSize ? left : rt::io::bufferSize;
    chars.reserve(wanted);
    size_t got = rt::io::readBytes(file, chars.bytes + chars.length, wanted);
    chars.length += got;
    if (got < wanted)
      break;
  }
  if (chars.length == 0)
    return rt::io::nullHandle;
  return programString(chars);
}

// fgetc's: the next byte of a stream, 0 to 255, or -1 at its end, on a
// failure, or when the handle is no stream to read from.
extern "C" int64_t idris_rt_io_file_read_char(int64_t file) {
  rt::io::ByteRead read =
      rt::io::withStream(file, [](const rt::io::Stream auto &stream) { return stream.readByte(); });
  return read.got == Got::Byte ? read.byte : -1;
}

// Skips a stream through its next '\n': 0, also at its end; -1 when a read
// failed or the handle is no stream to read from.
extern "C" int64_t idris_rt_io_file_seek_line(int64_t file) {
  return rt::io::withStream(file, [](const rt::io::Stream auto &stream) -> int64_t {
    rt::io::ByteRead read = stream.readByte();
    while (read.got == Got::Byte && read.byte != '\n')
      read = stream.readByte();
    return read.got == Got::Failure ? -1 : 0;
  });
}

// Writes all of a string's bytes to a stream, as fPutStr asks: 1 when they
// were written, 0 when the write failed or the handle is no stream to write
// to, even for the empty string.
extern "C" int64_t idris_rt_io_file_write_line(int64_t file, const idris_rt_str *line) {
  rt::io::Written written = rt::io::withStream(file, [&](const rt::io::Stream auto &stream) {
    return stream.write(idris_rt_str_bytes(line), line->bytes);
  });
  return written.failed ? 0 : 1;
}
