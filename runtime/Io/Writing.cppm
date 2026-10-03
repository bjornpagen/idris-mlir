// rt.io:writing: writing bytes to a file descriptor, and the size of the
// buffers of standard output and input.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>
#include <unistd.h>

export module rt.io:writing;

namespace rt::io {

inline constexpr size_t bufferSize = 4096;

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
