// rt.io:input: standard input, through a buffer that a read fills.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>

export module rt.io:input;

import rt.alloc;
import :writing;

namespace rt::io {

inline char input[bufferSize];
inline size_t inputPosition = 0;
inline size_t inputLength = 0;

} // namespace rt::io

namespace {

// Set once a read met the end of input: what C's feof reports.
bool inputEnded = false;

// A growable line being read: on the stack up to a page, then raw memory.
struct Line {
  char inline_[rt::io::bufferSize];
  char *bytes = inline_;
  size_t length = 0;
  size_t capacity = rt::io::bufferSize;
  ~Line() {
    if (bytes != inline_)
      rt::alloc::release(bytes);
  }
  void push(char c) {
    if (length == capacity) {
      auto *grown = static_cast<char *>(rt::alloc::allocate(capacity * 2));
      memcpy(grown, bytes, length);
      if (bytes != inline_)
        rt::alloc::release(bytes);
      bytes = grown;
      capacity *= 2;
    }
    bytes[length++] = c;
  }
};

} // namespace

namespace rt::io {

// The next input byte, or -1 at the end of input. Pending output is written
// before the program blocks reading.
int32_t peek() {
  if (inputPosition >= inputLength) {
    idris_rt_flush();
    ssize_t got = read(0, input, bufferSize);
    inputLength = got > 0 ? static_cast<size_t>(got) : 0;
    inputPosition = 0;
  }
  if (inputPosition < inputLength)
    return static_cast<unsigned char>(input[inputPosition]);
  inputEnded = true;
  return -1;
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
  Line line;
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

extern "C" int64_t idris_rt_io_eof(int64_t handle) { return handle == 0 && inputEnded ? 1 : 0; }
