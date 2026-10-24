// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Standard output and error. Output goes through one static buffer, flushed
// when it fills, before every read of standard input, before standard
// error's every write, and when the program ends, however it ends. The
// Prelude's output and base's writes of the handles 1 and 2, their streams,
// share it. A reader of either gone ends the program by the signal Unix
// tools die of, its other files written first.
#include "End/End.h"
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
using rt::io::bufferSize;

// The pending output and its length. An internal error met in the fault
// handler flushes it from a signal handler on the same thread, so the length is
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
  rt::io::flushOutput();
  return 0;
}

// A write of the program's own output: a reader gone ends the program; any
// other failure abandons the rest, as base's output reports none.
void written(rt::platform::Wrote how) {
  if (how == rt::platform::Wrote::Broken)
    rt::end::end(rt::end::Piped{});
}

// Standard output and error are never read: a read fails as on a stream not
// open for reading.
size_t readNothing() {
  rt::io::fail(EBADF);
  return 0;
}

ByteRead readNoByte() {
  rt::io::fail(EBADF);
  return {ByteRead::Got::Failure, 0};
}

} // namespace

namespace rt::io {

void putOutput(const char *p, size_t n) {
  size_t at = roomFor(n);
  if (n > bufferSize) {
    written(rt::platform::writeAll(1, p, n));
    return;
  }
  memcpy(output + at, p, n);
  publish(at + n);
}

char *outputRoom(size_t n) { return output + roomFor(n); }

void outputWritten(size_t n) { publish(outputLength.load(std::memory_order_relaxed) + n); }

// Standard output, the handle 1: written through the buffer, in order with
// every other write to it; flushing it, and closing it, write what it has
// pending, and it stays open. Its writes never fail (a reader gone ends the
// program), and it has no input to end.
Written OutputStream::write(const char *p, size_t n) const {
  putOutput(p, n);
  return {n, false};
}

size_t OutputStream::read(char *, size_t) const { return readNothing(); }

ByteRead OutputStream::readByte() const { return readNoByte(); }

bool OutputStream::flush() const {
  flushOutput();
  return true;
}

void OutputStream::close() const { flushOutput(); }

bool OutputStream::failed() const { return false; }

bool OutputStream::ended() const { return false; }

int OutputStream::descriptor() const { return 1; }

int64_t OutputStream::poll() const { return pollDescriptor(descriptor()); }

// Standard error, the handle 2: written at once, after what standard output
// has pending, so the two keep the order the program wrote them in; nothing
// is pending to flush, and closing it leaves it open. As standard output's,
// its writes never fail, and it has no input to end.
Written ErrorStream::write(const char *p, size_t n) const {
  flushOutput();
  written(rt::platform::writeAll(2, p, n));
  return {n, false};
}

size_t ErrorStream::read(char *, size_t) const { return readNothing(); }

ByteRead ErrorStream::readByte() const { return readNoByte(); }

bool ErrorStream::flush() const { return true; }

void ErrorStream::close() const {}

bool ErrorStream::failed() const { return false; }

bool ErrorStream::ended() const { return false; }

int ErrorStream::descriptor() const { return 2; }

int64_t ErrorStream::poll() const { return pollDescriptor(descriptor()); }

// The length is taken and 0 published before the write, so a flush an
// internal error makes in the middle of this one, from the fault handler,
// finds nothing left to write: the output is cut short, never written twice.
// The handler runs on this thread and does not return, so a plain load and
// store, kept in order by the fence, are the exchange it needs.
rt::platform::Wrote writePending() {
  size_t n = outputLength.load(std::memory_order_relaxed);
  outputLength.store(0, std::memory_order_relaxed);
  std::atomic_signal_fence(std::memory_order_seq_cst);
  return rt::platform::writeAll(1, output, n);
}

void flushOutput() { written(writePending()); }

} // namespace rt::io

// Writes a string's bytes.
extern "C" void idris_rt_io_put_str(const idris_rt_str *s) {
  rt::io::putOutput(idris_rt_str_bytes(s), s->bytes);
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
