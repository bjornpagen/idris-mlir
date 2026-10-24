// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Files, through the C library's streams, reading and writing a descriptor,
// and what the system says of an open descriptor, on a POSIX system. The
// names of a stat's times, where Linux and macOS differ, are the operating
// system's unit's (statTimes).
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

namespace {

// How a failed write went, by its errno: the reader of a pipe gone, or any
// other failure.
rt::platform::Wrote failed() noexcept {
  return errno == EPIPE ? rt::platform::Wrote::Broken : rt::platform::Wrote::Failed;
}

} // namespace

namespace rt::platform {

File *openFile(const char *path, const char *mode) noexcept { return fopen(path, mode); }

Wrote closeFile(File *file) noexcept { return fclose(file) == 0 ? Wrote::Whole : failed(); }

int descriptor(File *file) noexcept { return fileno(file); }

bool fileFailed(File *file) noexcept { return ferror(file) != 0; }

bool fileEnded(File *file) noexcept { return feof(file) != 0; }

int32_t readByte(File *file) noexcept {
  int c = getc(file);
  return c == EOF ? -1 : c;
}

size_t readFile(File *file, char *p, size_t n) noexcept { return fread(p, 1, n, file); }

FileWrote writeFile(File *file, const char *p, size_t n) noexcept {
  size_t count = fwrite(p, 1, n, file);
  return {count, count == n ? Wrote::Whole : failed()};
}

Wrote flushFile(File *file) noexcept { return fflush(file) == 0 ? Wrote::Whole : failed(); }

bool removeFile(const char *path) noexcept { return remove(path) == 0; }

bool changeMode(const char *path, int64_t mode) noexcept {
  return chmod(path, static_cast<mode_t>(mode)) == 0;
}

int64_t fileSize(int fd) noexcept {
  struct stat status {};
  if (fstat(fd, &status) != 0)
    return -1;
  return static_cast<int64_t>(status.st_size);
}

bool fileTimes(int fd, FileTimes &times) noexcept {
  struct stat status {};
  if (fstat(fd, &status) != 0)
    return false;
  const StatTimes stamps = statTimes(status);
  using enum idr::files::FileTimeField;
  times[AccessSeconds] = static_cast<int64_t>(stamps.access.tv_sec);
  times[AccessNanoseconds] = static_cast<int64_t>(stamps.access.tv_nsec);
  times[ModifiedSeconds] = static_cast<int64_t>(stamps.modified.tv_sec);
  times[ModifiedNanoseconds] = static_cast<int64_t>(stamps.modified.tv_nsec);
  times[StatusSeconds] = static_cast<int64_t>(stamps.changed.tv_sec);
  times[StatusNanoseconds] = static_cast<int64_t>(stamps.changed.tv_nsec);
  return true;
}

int64_t waitForInput(int fd) noexcept {
  if (fd < 0 || fd >= FD_SETSIZE) {
    errno = EINVAL;
    return -1;
  }
  fd_set ready;
  FD_ZERO(&ready);
  FD_SET(fd, &ready);
  struct timeval second {};
  second.tv_sec = 1;
  return select(fd + 1, &ready, nullptr, nullptr, &second);
}

bool isTerminal(int fd) noexcept { return isatty(fd) == 1; }

// A write a signal interrupts before it wrote anything is tried again, as
// the C library's stdio does; any other failure abandons the rest. errno is
// read here, inline, so nothing it calls leaves the baseline.
IDRIS_RT_BASELINE Wrote writeAll(int fd, const char *p, size_t n) noexcept {
  while (n > 0) {
    ssize_t written = write(fd, p, n);
    if (written < 0 && errno == EINTR)
      continue;
    if (written < 0)
      return errno == EPIPE ? Wrote::Broken : Wrote::Failed;
    if (written == 0)
      return Wrote::Failed;
    p += written;
    n -= static_cast<size_t>(written);
  }
  return Wrote::Whole;
}

int64_t readSome(int fd, char *p, size_t n) noexcept { return static_cast<int64_t>(read(fd, p, n)); }

} // namespace rt::platform
