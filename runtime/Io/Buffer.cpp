// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The copies and strings Data.Buffer builds on a byte array. A byte array
// comes as its cell, its first byte and its size; every span lies in it,
// since the compiler's range check before the call is its one test, and
// the runtime addresses it from the first byte alone. A machine word is the
// target's own load or store, in compiled code.
// PIN(runtime-quarantine) — see PINS.md
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

extern "C" void idris_rt_io_buffer_copy(idris_rt_array *, const char *src, int64_t,
                                        int64_t srcOffset, int64_t n, idris_rt_array *, char *dst,
                                        int64_t, int64_t dstOffset) {
  memmove(dst + dstOffset, src + srcOffset, static_cast<size_t>(n));
}

extern "C" void idris_rt_io_buffer_set_string(idris_rt_array *, char *bytes, int64_t,
                                              int64_t offset, const idris_rt_str *str) {
  int64_t n = idris_rt_str_bytes_length(str);
  memcpy(bytes + offset, idris_rt_str_bytes(str), static_cast<size_t>(n));
}

extern "C" const idris_rt_str *idris_rt_io_buffer_get_string(idris_rt_array *, const char *bytes,
                                                             int64_t, int64_t offset, int64_t n) {
  return idris_rt_str_from_bytes(bytes + offset, static_cast<size_t>(n));
}
