// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Bytes being gathered before they become a string or go to the C library:
// a line being read, a path.
#include "Alloc/Alloc.h"
#include "Io/Io.h"
#include "idris_rt.h"

#include <stddef.h>
#include <string.h>

namespace rt::io {

Scratch::~Scratch() {
  if (bytes != inline_)
    rt::alloc::release(bytes);
}

void Scratch::reserve(size_t n) {
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

void Scratch::append(const char *p, size_t n) {
  reserve(n);
  memcpy(bytes + length, p, n);
  length += n;
}

const char *cText(Scratch &scratch, const idris_rt_str *s) {
  scratch.append(idris_rt_str_bytes(s), static_cast<size_t>(s->bytes));
  scratch.push('\0');
  return scratch.bytes;
}

} // namespace rt::io
