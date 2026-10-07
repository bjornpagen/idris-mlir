// rt.io:writing: writing bytes to a file descriptor, and the size of the
// buffers of standard output and input.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>
#include <unistd.h>

export module rt.io:writing;

namespace rt::io {

// The size of the buffers of standard output and input: a buffer, not a
// page. It bounds one write's worth of pending output and is never an
// alignment or a region size (the target entry's page size is
// IDRIS_MLIR_PAGE_SIZE, which rt.platform's startup check reads); 4096 is a
// small write's worth on every target.
inline constexpr size_t bufferSize = 4096;

// Stores, which stay stores. A memcpy a compiler invents for the same copy
// can be dropped or moved past the length that publishes the bytes.
inline void copyOut(volatile char *to, const char *from, size_t n) {
  for (size_t i = 0; i < n; ++i)
    to[i] = from[i];
}

} // namespace rt::io

export namespace rt::io {

// Writes n bytes to fd, looping over partial writes; a failed write abandons
// the rest.
void writeAll(int fd, const char *p, size_t n) {
  while (n > 0) {
    ssize_t written = write(fd, p, n);
    size_t step = written > 0 ? static_cast<size_t>(written) : n;
    p += step;
    n -= step;
  }
}

} // namespace rt::io
