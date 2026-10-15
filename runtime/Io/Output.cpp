// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Standard output, through a buffer that a flush writes.
// PIN(runtime-quarantine) — see PINS.md
#include "Doubles/Doubles.h"
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <atomic>

namespace {

using rt::io::bufferSize;

// The pending output and its length. The program's stack running out
// flushes it from a signal handler on the same thread, so the length is
// published only after the bytes it covers are written: a relaxed atomic,
// which is a plain load and store, after a signal fence, which stops the
// compiler from moving the store above the copy and costs no instruction.
// The bytes themselves are a plain memcpy.
char output[bufferSize];
std::atomic<size_t> outputLength{0};

void publish(size_t length) {
  std::atomic_signal_fence(std::memory_order_release);
  outputLength.store(length, std::memory_order_relaxed);
}

// Where n more bytes go: the buffer's end, after a flush when they would
// not fit.
size_t roomFor(size_t n) {
  size_t at = outputLength.load(std::memory_order_relaxed);
  if (at + n <= bufferSize)
    return at;
  idris_rt_flush();
  return 0;
}

} // namespace

namespace rt::io {

void putBytes(const char *p, size_t n) {
  size_t at = roomFor(n);
  if (n > bufferSize) {
    rt::platform::writeAll(1, p, n);
    return;
  }
  memcpy(output + at, p, n);
  publish(at + n);
}

} // namespace rt::io

// The length is taken and 0 published before the write, so a flush the
// stack running out makes in the middle of this one finds nothing left to
// write: the output is cut short, never written twice. The handler runs on
// this thread and does not return, so a plain load and store, kept in order
// by the fence, are the exchange it needs.
extern "C" void idris_rt_flush(void) {
  size_t n = outputLength.load(std::memory_order_relaxed);
  outputLength.store(0, std::memory_order_relaxed);
  std::atomic_signal_fence(std::memory_order_seq_cst);
  rt::platform::writeAll(1, output, n);
}

extern "C" void idris_rt_io_put_str(const idris_rt_str *s) {
  rt::io::putBytes(idris_rt_str_bytes(s), s->bytes);
}

// A character is encoded where it goes, with no copy: room for the longest
// encoding first.
extern "C" void idris_rt_io_put_char(int32_t c) {
  size_t at = roomFor(4);
  publish(at + rt::strings::encodeUtf8(c, output + at));
}

extern "C" void idris_rt_io_put_int_s(int64_t value) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::strings::formatSigned(value, end);
  rt::io::putBytes(start, static_cast<size_t>(end - start));
}

extern "C" void idris_rt_io_put_int_u(uint64_t value) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::strings::formatUnsigned(value, end);
  rt::io::putBytes(start, static_cast<size_t>(end - start));
}

extern "C" void idris_rt_io_put_double(double value) {
  char text[rt::doubles::doubleTextMax];
  rt::io::putBytes(text, rt::doubles::formatDouble(value, text));
}
