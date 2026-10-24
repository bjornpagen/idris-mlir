// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The copies and strings Data.Buffer builds on a byte array, which comes as
// its cell (idris_rt_array_bytes). A machine word is the target's own load or
// store, in compiled code.
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

// Copies `len` bytes from one byte array to another. The ranges may
// overlap.
extern "C" void idris_rt_io_buffer_copy(idris_rt_array *src, int64_t srcOffset, int64_t len,
                                        idris_rt_array *dst, int64_t dstOffset) {
  memmove(idris_rt_array_bytes(dst) + dstOffset, idris_rt_array_bytes(src) + srcOffset,
          static_cast<size_t>(len));
}

// Writes a string's bytes at `offset`: the span is the string's byte length.
extern "C" void idris_rt_io_buffer_set_string(idris_rt_array *buffer, int64_t offset,
                                              const idris_rt_str *str) {
  memcpy(idris_rt_array_bytes(buffer) + offset, idris_rt_str_bytes(str), str->bytes);
}

// The bytes [offset, offset + len) of a byte array as a string, a new one or
// the persistent empty one. Ill-formed UTF-8 is replaced as
// idris_rt_str_from_bytes replaces it.
extern "C" const idris_rt_str *idris_rt_io_buffer_get_string(idris_rt_array *buffer, int64_t offset,
                                                             int64_t len) {
  return idris_rt_str_from_bytes(idris_rt_array_bytes(buffer) + offset, static_cast<size_t>(len));
}
