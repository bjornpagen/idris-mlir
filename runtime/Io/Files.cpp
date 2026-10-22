// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Base's files (System.File): opening a file, its stream, what base asks of
// any stream, and the files at a path. An open file is a slot of the handle
// table holding the C library's stream; the standard streams are the
// table's first slots, streams of their own (Input.cpp, Output.cpp), and
// stay open.
// PIN(runtime-quarantine) — see PINS.md
#include "End/End.h"
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace {

// How a write, a flush or a close of a file went, which a reader of a pipe
// gone ends the program by, written first everything else: true when it
// wrote everything, false with errno saved when it failed.
bool wrote(rt::platform::Wrote how) {
  switch (how) {
  case rt::platform::Wrote::Whole:
    return true;
  case rt::platform::Wrote::Broken:
    rt::end::end(rt::end::Piped{});
  case rt::platform::Wrote::Failed:
    rt::io::saveError();
    return false;
  }
}

} // namespace

namespace rt::io {

// An open file: the C library's stream, which buffers it, so its failure and
// its end are the stream's indicators, ferror's and feof's. Closing it
// writes what it has pending and frees its handle.
Written FileStream::write(const char *p, size_t n) const {
  rt::platform::FileWrote written = rt::platform::writeFile(file, p, n);
  return {written.count, !wrote(written.how)};
}

size_t FileStream::read(char *p, size_t n) const {
  size_t got = rt::platform::readFile(file, p, n);
  if (got < n && rt::platform::fileFailed(file))
    saveError();
  return got;
}

ByteRead FileStream::readByte() const {
  int32_t b = rt::platform::readByte(file);
  if (b >= 0)
    return {ByteRead::Got::Byte, static_cast<unsigned char>(b)};
  if (!rt::platform::fileFailed(file))
    return {ByteRead::Got::End, 0};
  saveError();
  return {ByteRead::Got::Failure, 0};
}

bool FileStream::flush() const { return wrote(rt::platform::flushFile(file)); }

void FileStream::close() const { (void)wrote(releaseSlot(handle)); }

bool FileStream::failed() const { return rt::platform::fileFailed(file); }

bool FileStream::ended() const { return rt::platform::fileEnded(file); }

int FileStream::descriptor() const { return rt::platform::descriptor(file); }

int64_t FileStream::poll() const { return pollDescriptor(descriptor()); }

int64_t pollDescriptor(int descriptor) {
  int64_t ready = rt::platform::waitForInput(descriptor);
  if (ready < 0)
    saveError();
  return ready;
}

} // namespace rt::io

// fopen's: the file at a path, opened in a mode ("r", "w", "a", with "+" or
// "b" as base's Mode writes them), as a new file handle; null when it cannot
// be opened.
extern "C" int64_t idris_rt_io_file_open(const idris_rt_str *path, const idris_rt_str *mode) {
  rt::io::Scratch pathText;
  rt::io::Scratch modeText;
  rt::platform::File *file =
      rt::platform::openFile(rt::io::cText(pathText, path), rt::io::cText(modeText, mode));
  if (file == nullptr) {
    rt::io::saveError();
    return idr::handles::nullHandle;
  }
  int64_t handle = rt::io::newSlot(rt::io::Kind::File);
  rt::io::slotOf(handle).file = file;
  return handle;
}

// fclose's: closes a file, writing what it has pending, and frees its
// handle. A standard stream stays open, since the runtime writes and reads
// it: closing standard output writes what it has pending.
extern "C" void idris_rt_io_file_close(int64_t file) {
  rt::io::withStream(file, [](const rt::io::Stream auto &stream) { stream.close(); });
}

// ferror's: 1 once a read or a write on the stream failed, else 0. A handle
// that is not open has failed (EBADF).
extern "C" int64_t idris_rt_io_file_error(int64_t file) {
  return rt::io::withStream(file, [](const rt::io::Stream auto &stream) -> int64_t {
    return stream.failed() ? 1 : 0;
  });
}

// feof's: 1 once a read on the stream met the end of its input, else 0:
// standard input's end, or an open file's. Standard output and error have
// none, and a handle that is not open has none either (EBADF).
extern "C" int64_t idris_rt_io_eof(int64_t handle) {
  return rt::io::withStream(handle, [](const rt::io::Stream auto &stream) -> int64_t {
    return stream.ended() ? 1 : 0;
  });
}

// fflush's: writes what the stream has pending, 0, or -1 when that failed or
// the handle is not open. Standard output writes its buffer; standard input
// and error have nothing pending.
extern "C" int64_t idris_rt_io_file_flush(int64_t file) {
  return rt::io::withStream(file, [](const rt::io::Stream auto &stream) -> int64_t {
    return stream.flush() ? 0 : -1;
  });
}

// remove's: 0, or -1 when the file at the path cannot be removed.
extern "C" int64_t idris_rt_io_file_remove(const idris_rt_str *path) {
  rt::io::Scratch text;
  if (rt::platform::removeFile(rt::io::cText(text, path)))
    return 0;
  rt::io::saveError();
  return -1;
}

// chmod's: sets the permission bits of the file at the path to `mode`; 0, or
// -1 when it cannot.
extern "C" int64_t idris_rt_io_file_chmod(const idris_rt_str *path, int64_t mode) {
  rt::io::Scratch text;
  if (rt::platform::changeMode(rt::io::cText(text, path), mode))
    return 0;
  rt::io::saveError();
  return -1;
}

// The size in bytes of the file the handle names, as fstat gives it (what a
// file's stream has pending is not in it yet), or -1 when it cannot be read.
// A handle that is not open has no descriptor, which fstat refuses as such.
extern "C" int64_t idris_rt_io_file_size(int64_t file) {
  int64_t size = rt::platform::fileSize(rt::io::descriptorOf(file));
  if (size < 0)
    rt::io::saveError();
  return size;
}

// Whether the stream has input ready, waiting up to a second for it, as
// select says: 1 when it has, 0 when it has not, -1 on a failure or when the
// handle is not open.
extern "C" int64_t idris_rt_io_file_poll(int64_t file) {
  return rt::io::withStream(file, [](const rt::io::Stream auto &stream) { return stream.poll(); });
}

// isatty's: 1 when the stream is a terminal, else 0, as for a handle that is
// not open, whose missing descriptor isatty refuses.
extern "C" int64_t idris_rt_io_file_is_tty(int64_t file) {
  return rt::platform::isTerminal(rt::io::descriptorOf(file)) ? 1 : 0;
}
