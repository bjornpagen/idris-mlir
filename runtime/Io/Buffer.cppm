// rt.io:buffer: the address of a span of a byte array, and the copies and
// strings Data.Buffer builds on it. One check: the span lies in the array,
// the same one a transfer to a file uses. A machine word is then the
// target's own load or store of that address.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>
#include <string.h>

export module rt.io:buffer;

extern "C" char *idris_rt_buffer_at(idris_rt_array *buf, int64_t length, int64_t offset,
                                    int64_t bytes) {
  if (offset < 0 || bytes < 0 || offset > length || bytes > length - offset) {
    static constexpr char message[] = "idris-mlir: a byte range outside the buffer\n";
    idris_rt_crash(message, sizeof message - 1);
  }
  return reinterpret_cast<char *>(buf + 1) + offset;
}

extern "C" void idris_rt_io_buffer_copy(idris_rt_array *src, int64_t srcLen, int64_t srcOff,
                                        int64_t n, idris_rt_array *dst, int64_t dstLen,
                                        int64_t dstOff) {
  char *from = idris_rt_buffer_at(src, srcLen, srcOff, n);
  char *to = idris_rt_buffer_at(dst, dstLen, dstOff, n);
  memmove(to, from, static_cast<size_t>(n));
}

extern "C" void idris_rt_io_buffer_set_string(idris_rt_array *buf, int64_t length, int64_t offset,
                                              const idris_rt_str *str) {
  int64_t n = idris_rt_str_bytes_length(str);
  char *to = idris_rt_buffer_at(buf, length, offset, n);
  memcpy(to, idris_rt_str_bytes(str), static_cast<size_t>(n));
}

extern "C" const idris_rt_str *idris_rt_io_buffer_get_string(idris_rt_array *buf, int64_t length,
                                                             int64_t offset, int64_t n) {
  const char *from = idris_rt_buffer_at(buf, length, offset, n);
  return idris_rt_str_from_bytes(from, static_cast<size_t>(n));
}
