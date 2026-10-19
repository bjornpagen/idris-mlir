// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Files, through the C library's streams, reading and writing a descriptor,
// and what the system says of an open descriptor, on a POSIX system. Where Linux and macOS differ, in the
// fields of a stat's times, one function holds it.
// PIN(runtime-quarantine) — see PINS.md
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

namespace rt::platform {

File *openFile(const char *path, const char *mode) noexcept { return fopen(path, mode); }

bool closeFile(File *file) noexcept { return fclose(file) == 0; }

int descriptor(File *file) noexcept { return fileno(file); }

bool fileFailed(File *file) noexcept { return ferror(file) != 0; }

bool fileEnded(File *file) noexcept { return feof(file) != 0; }

int32_t readByte(File *file) noexcept {
  int c = getc(file);
  return c == EOF ? -1 : c;
}

size_t readFile(File *file, char *p, size_t n) noexcept { return fread(p, 1, n, file); }

size_t writeFile(File *file, const char *p, size_t n) noexcept { return fwrite(p, 1, n, file); }

bool flushFile(File *file) noexcept { return fflush(file) == 0; }

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

// POSIX names the fields st_atim and its kin; Darwin, whose stat predates
// them, st_atimespec.
bool fileTimes(int fd, int64_t (&times)[6]) noexcept {
  struct stat status {};
  if (fstat(fd, &status) != 0)
    return false;
#if defined(__APPLE__)
  const struct timespec *spans[] = {&status.st_atimespec, &status.st_mtimespec,
                                    &status.st_ctimespec};
#else
  const struct timespec *spans[] = {&status.st_atim, &status.st_mtim, &status.st_ctim};
#endif
  for (size_t i = 0; i < 3; ++i) {
    times[2 * i] = static_cast<int64_t>(spans[i]->tv_sec);
    times[2 * i + 1] = static_cast<int64_t>(spans[i]->tv_nsec);
  }
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
// the C library's stdio does; any other failure abandons the rest.
IDRIS_RT_BASELINE void writeAll(int fd, const char *p, size_t n) noexcept {
  while (n > 0) {
    ssize_t written = write(fd, p, n);
    if (written < 0 && errno == EINTR)
      continue;
    if (written <= 0)
      return;
    p += written;
    n -= static_cast<size_t>(written);
  }
}

IDRIS_RT_BASELINE void writeCrash(const Piece *pieces, size_t count) noexcept {
  static constexpr char prefix[] = "idris-mlir: ";
  writeAll(2, prefix, sizeof prefix - 1);
  for (size_t i = 0; i < count; ++i)
    writeAll(2, pieces[i].bytes, pieces[i].length);
  writeAll(2, "\n", 1);
}

int64_t readSome(int fd, char *p, size_t n) noexcept { return static_cast<int64_t>(read(fd, p, n)); }

} // namespace rt::platform
