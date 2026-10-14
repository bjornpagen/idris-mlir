// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Writing bytes to a file descriptor.
// PIN(runtime-quarantine) — see PINS.md
#include "Io/Io.h"

#include <stddef.h>
#include <sys/types.h>
#include <unistd.h>

namespace rt::io {

void writeAll(int fd, const char *p, size_t n) {
  while (n > 0) {
    ssize_t written = write(fd, p, n);
    size_t step = written > 0 ? static_cast<size_t>(written) : n;
    p += step;
    n -= step;
  }
}

} // namespace rt::io
