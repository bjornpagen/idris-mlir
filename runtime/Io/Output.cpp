// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Standard output and error. Output goes through one static buffer, flushed
// when it fills, before every read of standard input, before standard
// error's every write and a crash's message, and when main returns or the
// program exits. The Prelude's output and base's writes of the handles 1
// and 2, their streams, share it.
// PIN(runtime-quarantine) — see PINS.md
#include "Doubles/Doubles.h"
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <atomic>

namespace {

using rt::io::ByteRead;
using rt::io::Stream;
using rt::io::Written;
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

// The n bytes at p, after what is pending: into the buffer, or, when they
// are more than it holds, written at once after it.
void putBytes(const char *p, size_t n) {
  size_t at = roomFor(n);
  if (n > bufferSize) {
    rt::platform::writeAll(1, p, n);
    return;
  }
  memcpy(output + at, p, n);
  publish(at + n);
}

// Standard output and error are never read: a read fails as on a stream not
// open for reading.
size_t readNothing(const Stream &, char *, size_t) {
  rt::io::fail(EBADF);
  return 0;
}

ByteRead readNoByte(const Stream &) {
  rt::io::fail(EBADF);
  return {ByteRead::Got::Failure, 0};
}

// Their writes never fail and they have no input to end.
bool never(const Stream &) { return false; }

} // namespace

namespace rt::io {

// Standard output, the handle 1: written through the buffer, in order with
// every other write to it; flushing it, and closing it, write what it has
// pending, and it stays open.
constexpr StreamOps outputStream{
    .write =
        [](const Stream &, const char *p, size_t n) {
          putBytes(p, n);
          return Written{n, false};
        },
    .read = readNothing,
    .readByte = readNoByte,
    .flush =
        [](const Stream &) {
          idris_rt_flush();
          return true;
        },
    .close = [](const Stream &) { idris_rt_flush(); },
    .failed = never,
    .ended = never,
    .descriptor = [](const Stream &) { return 1; },
    .poll = pollDescriptor,
};

// Standard error, the handle 2: written at once, after what standard output
// has pending, so the two keep the order the program wrote them in; nothing
// is pending to flush, and closing it leaves it open.
constexpr StreamOps errorStream{
    .write =
        [](const Stream &, const char *p, size_t n) {
          idris_rt_flush();
          rt::platform::writeAll(2, p, n);
          return Written{n, false};
        },
    .read = readNothing,
    .readByte = readNoByte,
    .flush = [](const Stream &) { return true; },
    .close = [](const Stream &) {},
    .failed = never,
    .ended = never,
    .descriptor = [](const Stream &) { return 2; },
    .poll = pollDescriptor,
};

} // namespace rt::io

// Writes pending output. The length is taken and 0 published before the
// write, so a flush the stack running out makes in the middle of this one
// finds nothing left to write: the output is cut short, never written twice.
// The handler runs on this thread and does not return, so a plain load and
// store, kept in order by the fence, are the exchange it needs.
extern "C" void idris_rt_flush(void) {
  size_t n = outputLength.load(std::memory_order_relaxed);
  outputLength.store(0, std::memory_order_relaxed);
  std::atomic_signal_fence(std::memory_order_seq_cst);
  rt::platform::writeAll(1, output, n);
}

// Writes a string's bytes.
extern "C" void idris_rt_io_put_str(const idris_rt_str *s) {
  putBytes(idris_rt_str_bytes(s), s->bytes);
}

// Writes the UTF-8 encoding of a character: the Prelude's putChar, and what
// writing a one-character string writes. A Char is a Unicode scalar value,
// so it is written whole, where both stock backends call C's putchar, as the
// Prelude declares putChar, and write its low byte. It is encoded where it
// goes, with no copy: room for the longest encoding first.
extern "C" void idris_rt_io_put_char(int32_t c) {
  size_t at = roomFor(4);
  publish(at + rt::strings::encodeUtf8(c, output + at));
}

// Write the decimal text of a signed or an unsigned integer, which idr-lower
// extends to 64 bits as its type's signedness says.
extern "C" void idris_rt_io_put_int_s(int64_t value) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::strings::formatSigned(value, end);
  putBytes(start, static_cast<size_t>(end - start));
}

extern "C" void idris_rt_io_put_int_u(uint64_t value) {
  char text[rt::strings::intTextMax];
  char *end = text + sizeof text;
  char *start = rt::strings::formatUnsigned(value, end);
  putBytes(start, static_cast<size_t>(end - start));
}

// Writes the text of a double, as idris_rt_str_show_f64 writes it.
extern "C" void idris_rt_io_put_double(double value) {
  char text[rt::doubles::doubleTextMax];
  putBytes(text, rt::doubles::formatDouble(value, text));
}
