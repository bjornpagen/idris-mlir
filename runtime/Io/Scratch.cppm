// rt.io:scratch: bytes being gathered before they become a string or go to
// the C library: a line being read, a path.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <string.h>

export module rt.io:scratch;

import rt.alloc;
import :writing;

namespace rt::io {

// A growable run of bytes: on the stack up to a buffer's worth, then raw
// memory.
struct Scratch {
  char inline_[bufferSize];
  char *bytes = inline_;
  size_t length = 0;
  size_t capacity = bufferSize;
  ~Scratch() {
    if (bytes != inline_)
      rt::alloc::release(bytes);
  }
  // Room for n more bytes, from bytes + length.
  void reserve(size_t n) {
    if (capacity - length >= n)
      return;
    size_t grown = capacity * 2;
    while (grown - length < n)
      grown *= 2;
    auto *to = static_cast<char *>(rt::alloc::allocate(grown));
    memcpy(to, bytes, length);
    if (bytes != inline_)
      rt::alloc::release(bytes);
    bytes = to;
    capacity = grown;
  }
  void push(char c) {
    reserve(1);
    bytes[length++] = c;
  }
  void append(const char *p, size_t n) {
    reserve(n);
    memcpy(bytes + length, p, n);
    length += n;
  }
};

// A string as the C library takes one: its bytes, gathered in `scratch`, and
// a NUL after them. A NUL in the string ends it there.
const char *cText(Scratch &scratch, const idris_rt_str *s) {
  scratch.append(idris_rt_str_bytes(s), static_cast<size_t>(s->bytes));
  scratch.push('\0');
  return scratch.bytes;
}

} // namespace rt::io
