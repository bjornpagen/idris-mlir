// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Standard input, through a buffer that a read fills: the Prelude's getChar
// and getLine and base's reads of the handle 0, its stream, share it, so they
// interleave on one input without losing a byte.
// PIN(runtime-quarantine) — see PINS.md
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace {

using rt::io::ByteRead;
using rt::io::Stream;
using rt::io::Written;
using rt::io::bufferSize;

char input[bufferSize];
size_t inputPosition = 0;
size_t inputLength = 0;
// Set once a read failed: what C's ferror reports, which base asks after a
// read that gave nothing.
bool inputFailed = false;
// Set once a read met the end of input: what C's feof reports.
bool inputEnded = false;

// The next input byte, or -1 at the end of input or when the read failed.
// Pending output is written before the program blocks reading.
int32_t peek() {
  if (inputPosition >= inputLength) {
    idris_rt_flush();
    int64_t got = rt::platform::readSome(0, input, bufferSize);
    if (got < 0) {
      inputFailed = true;
      rt::io::saveError();
    }
    inputLength = got > 0 ? static_cast<size_t>(got) : 0;
    inputPosition = 0;
  }
  if (inputPosition < inputLength)
    return static_cast<unsigned char>(input[inputPosition]);
  inputEnded = true;
  return -1;
}

// Up to `count` input bytes into `to`, waiting for each until the end of
// input: fewer only there.
size_t readInput(char *to, size_t count) {
  size_t got = 0;
  while (got < count && peek() >= 0) {
    size_t available = inputLength - inputPosition;
    size_t wanted = count - got;
    size_t step = available < wanted ? available : wanted;
    memcpy(to + got, input + inputPosition, step);
    inputPosition += step;
    got += step;
  }
  return got;
}

} // namespace

namespace rt::io {

// Standard input, the handle 0: read through the buffer, never written (a
// write fails as on a stream not open for writing), with nothing pending to
// flush; its end and its failure are the buffer's reads'; its descriptor is
// 0, which has input ready too while the buffer holds unread bytes; closing
// it leaves it open.
constexpr StreamOps inputStream{
    .write =
        [](const Stream &, const char *, size_t) {
          fail(EBADF);
          return Written{0, true};
        },
    .read = [](const Stream &, char *p, size_t n) { return readInput(p, n); },
    .readByte =
        [](const Stream &) {
          int32_t b = peek();
          if (b < 0)
            return ByteRead{inputFailed ? ByteRead::Got::Failure : ByteRead::Got::End, 0};
          ++inputPosition;
          return ByteRead{ByteRead::Got::Byte, static_cast<unsigned char>(b)};
        },
    .flush = [](const Stream &) { return true; },
    .close = [](const Stream &) {},
    .failed = [](const Stream &) { return inputFailed; },
    .ended = [](const Stream &) { return inputEnded; },
    .descriptor = [](const Stream &) { return 0; },
    .poll = [](const Stream &stream) -> int64_t {
      return inputPosition < inputLength ? 1 : pollDescriptor(stream);
    },
};

} // namespace rt::io

// The Prelude's getChar: one byte, or 255 at the end of input, which the
// Prelude's Char has no room to tell apart.
extern "C" int32_t idris_rt_io_get_byte(void) {
  int32_t b = peek();
  if (b < 0)
    return 255;
  ++inputPosition;
  return b;
}

// The Prelude's getLine: a line of input without its end, a new string. A
// line ends at '\n', as POSIX reads text, or at the "\r\n" that ends the
// lines of text written elsewhere: the bytes up to the next '\n', which is
// consumed, without that '\n' or the "\r\n" it ends; the rest of the input
// when no '\n' is left, and the empty string at the end of input. A '\r'
// anywhere else is the line's own. The bytes are decoded as
// idris_rt_str_from_bytes decodes them.
extern "C" const idris_rt_str *idris_rt_io_get_line(void) {
  rt::io::Scratch line;
  for (int32_t b = peek(); b >= 0; b = peek()) {
    ++inputPosition;
    if (b == '\n') {
      if (line.length > 0 && line.bytes[line.length - 1] == '\r')
        --line.length;
      break;
    }
    line.push(static_cast<char>(b));
  }
  return idris_rt_str_from_bytes(line.bytes, line.length);
}
