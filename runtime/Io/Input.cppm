// rt.io:input: standard input, through a buffer that a read fills: the
// Prelude's getLine and base's reads of the handle 0 share it.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <unistd.h>

export module rt.io:input;

import rt.platform;
import :errors;
import :handles;
import :scratch;
import :writing;

namespace rt::io {

inline char input[bufferSize];
inline size_t inputPosition = 0;
inline size_t inputLength = 0;
// Set once a read failed: what C's ferror reports, which base asks after a
// read that gave nothing.
inline bool inputFailed = false;

} // namespace rt::io

namespace {

// Set once a read met the end of input: what C's feof reports.
bool inputEnded = false;

} // namespace

namespace rt::io {

// The next input byte, or -1 at the end of input or when the read failed.
// Pending output is written before the program blocks reading.
int32_t peek() {
  if (inputPosition >= inputLength) {
    idris_rt_flush();
    ssize_t got = read(0, input, bufferSize);
    if (got < 0) {
      inputFailed = true;
      saveError();
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
// input: fewer only there. Gives the count read.
size_t readInput(char *to, size_t count) {
  size_t got = 0;
  while (got < count && peek() >= 0) {
    size_t available = inputLength - inputPosition;
    size_t wanted = count - got;
    size_t step = available < wanted ? available : wanted;
    copyOut(to + got, input + inputPosition, step);
    inputPosition += step;
    got += step;
  }
  return got;
}

} // namespace rt::io

extern "C" int32_t idris_rt_io_get_byte(void) {
  int32_t b = rt::io::peek();
  if (b < 0)
    return 255;
  ++rt::io::inputPosition;
  return b;
}

// A line ends at '\n', as POSIX reads text, or at the "\r\n" that ends the
// lines of text written elsewhere; a '\r' anywhere else is the line's own.
extern "C" const idris_rt_str *idris_rt_io_get_line(void) {
  rt::io::Scratch line;
  for (int32_t b = rt::io::peek(); b >= 0; b = rt::io::peek()) {
    ++rt::io::inputPosition;
    if (b == '\n') {
      if (line.length > 0 && line.bytes[line.length - 1] == '\r')
        --line.length;
      break;
    }
    line.push(static_cast<char>(b));
  }
  return idris_rt_str_from_bytes(line.bytes, line.length);
}

// feof's: standard input's end, or an open file's. Standard output and error
// have none, and a handle that is not open has none either (EBADF).
extern "C" int64_t idris_rt_io_eof(int64_t handle) {
  if (handle == 0)
    return inputEnded ? 1 : 0;
  if (handle > 0 && handle < rt::io::firstHandle)
    return 0;
  rt::platform::File *file = rt::io::fileOf(handle);
  return file != nullptr && rt::platform::fileEnded(file) ? 1 : 0;
}
