// rt.platform:files: files, through the C library's streams, and what the
// system says of an open descriptor, on a POSIX system. Where Linux and macOS
// differ, in the fields of a stat's times, one function holds it.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/select.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

export module rt.platform:files;

export namespace rt::platform {

// An open file: the C library's stream, which buffers it.
using File = FILE;

// fopen's: the file at a path in a mode ("r", "w+", ...), or null.
File *openFile(const char *path, const char *mode) noexcept { return fopen(path, mode); }

// Closes the stream, writing what it has pending; false when that failed.
// The stream is gone either way.
bool closeFile(File *file) noexcept { return fclose(file) == 0; }

int descriptor(File *file) noexcept { return fileno(file); }

// The stream's error indicator: a read or a write on it failed.
bool fileFailed(File *file) noexcept { return ferror(file) != 0; }

// The stream's end-of-file indicator: a read met the end of the file.
bool fileEnded(File *file) noexcept { return feof(file) != 0; }

// The next byte, or -1 at the end of the file or on a failure, which
// fileFailed tells apart.
int32_t readByte(File *file) noexcept {
  int c = getc(file);
  return c == EOF ? -1 : c;
}

// Up to n bytes into p: fewer at the end of the file or on a failure.
size_t readFile(File *file, char *p, size_t n) noexcept { return fread(p, 1, n, file); }

// The n bytes at p, through the stream's buffer: fewer on a failure.
size_t writeFile(File *file, const char *p, size_t n) noexcept { return fwrite(p, 1, n, file); }

bool flushFile(File *file) noexcept { return fflush(file) == 0; }

bool removeFile(const char *path) noexcept { return remove(path) == 0; }

bool changeMode(const char *path, int64_t mode) noexcept {
  return chmod(path, static_cast<mode_t>(mode)) == 0;
}

// The size in bytes of what the descriptor names, or -1.
int64_t fileSize(int fd) noexcept {
  struct stat status {};
  if (fstat(fd, &status) != 0)
    return -1;
  return static_cast<int64_t>(status.st_size);
}

// The access, modification and status change times of what the descriptor
// names, each as seconds and nanoseconds, in that order; false when they
// cannot be read. POSIX names the fields st_atim and its kin; Darwin, whose
// stat predates them, st_atimespec.
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

// Whether the descriptor has input ready, waiting up to a second for it, as
// base's fPoll does in C: 1 when it has, 0 when the second passed, -1 on a
// failure. A descriptor select cannot watch is a failure too.
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

} // namespace rt::platform
