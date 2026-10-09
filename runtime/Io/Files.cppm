// rt.io:files: base's files (System.File): opening and closing one, its
// stream's state, and the files at a path. An open file is a slot of the
// handle table holding the C library's stream; the standard streams are the
// handles 0, 1 and 2, which the runtime's own buffers serve, and stay open.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>

export module rt.io:files;

import rt.platform;
import :errors;
import :handles;
import :input;
import :scratch;

namespace rt::io {

// The descriptor of a standard stream or an open file, or -1 when the handle
// is neither (EBADF).
int descriptorOf(int64_t handle) {
  if (handle >= 0 && handle < firstHandle)
    return static_cast<int>(handle);
  rt::platform::File *file = fileOf(handle);
  return file == nullptr ? -1 : rt::platform::descriptor(file);
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
    return rt::io::nullHandle;
  }
  int64_t handle = rt::io::newSlot(rt::io::Kind::File);
  rt::io::slotOf(handle)->file = file;
  return handle;
}

// Closes a file, writing what it has pending, and frees its handle. A
// standard stream stays open, since the runtime writes and reads it: closing
// standard output writes what it has pending, and the other two need
// nothing.
extern "C" void idris_rt_io_file_close(int64_t file) {
  if (file >= 0 && file < rt::io::firstHandle) {
    if (file == 1)
      idris_rt_flush();
    return;
  }
  if (rt::io::fileOf(file) != nullptr)
    rt::io::releaseSlot(file);
}

// ferror's: 1 once a read or a write on the file failed, else 0. A handle
// that is not open has failed (EBADF).
extern "C" int64_t idris_rt_io_file_error(int64_t file) {
  if (file == 0)
    return rt::io::inputFailed ? 1 : 0;
  if (file > 0 && file < rt::io::firstHandle)
    return 0;
  rt::platform::File *stream = rt::io::fileOf(file);
  return stream == nullptr || rt::platform::fileFailed(stream) ? 1 : 0;
}

// fflush's: writes what the file has pending, 0, or -1 when that failed or
// the handle is not open. Standard output writes its buffer; standard input
// and error have nothing pending.
extern "C" int64_t idris_rt_io_file_flush(int64_t file) {
  if (file >= 0 && file < rt::io::firstHandle) {
    if (file == 1)
      idris_rt_flush();
    return 0;
  }
  rt::platform::File *stream = rt::io::fileOf(file);
  if (stream == nullptr)
    return -1;
  if (rt::platform::flushFile(stream))
    return 0;
  rt::io::saveError();
  return -1;
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
extern "C" int64_t idris_rt_io_file_size(int64_t file) {
  int fd = rt::io::descriptorOf(file);
  if (fd < 0)
    return -1;
  int64_t size = rt::platform::fileSize(fd);
  if (size < 0)
    rt::io::saveError();
  return size;
}

// Whether the file has input ready, waiting up to a second for it, as
// select says: 1 when it has, 0 when it has not, -1 on a failure. Standard
// input has input ready while its buffer holds unread bytes.
extern "C" int64_t idris_rt_io_file_poll(int64_t file) {
  if (file == 0 && rt::io::inputPosition < rt::io::inputLength)
    return 1;
  int fd = rt::io::descriptorOf(file);
  if (fd < 0)
    return -1;
  int64_t ready = rt::platform::waitForInput(fd);
  if (ready < 0)
    rt::io::saveError();
  return ready;
}

// isatty's: 1 when the file is a terminal, else 0.
extern "C" int64_t idris_rt_io_file_is_tty(int64_t file) {
  int fd = rt::io::descriptorOf(file);
  return fd >= 0 && rt::platform::isTerminal(fd) ? 1 : 0;
}
