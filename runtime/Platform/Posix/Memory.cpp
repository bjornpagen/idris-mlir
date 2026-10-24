// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Address space and memory, by the page, on a POSIX system: reserved
// inaccessible, which no host counts as memory, then committed as used.
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <unistd.h>

namespace rt::platform {

// sysconf's: on Darwin hw.pagesize and vm_page_size alike, 16 KiB for an
// arm64 process.
IDRIS_RT_BASELINE size_t systemPageSize() noexcept {
  return static_cast<size_t>(sysconf(_SC_PAGESIZE));
}

// An inaccessible mapping is no memory to any host: Linux charges a private
// mapping to its commit limit only once it is writable, under every
// overcommit mode, so a reservation needs no flag to escape the charge.
char *reserve(size_t size) noexcept {
  void *region = mmap(nullptr, size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  return region == MAP_FAILED ? nullptr : static_cast<char *>(region);
}

bool commit(char *p, size_t n) noexcept { return mprotect(p, n, PROT_READ | PROT_WRITE) == 0; }

void release(char *p, size_t size) noexcept { munmap(p, size); }

size_t addressSpaceLimit() noexcept {
  struct rlimit space {};
  if (getrlimit(RLIMIT_AS, &space) != 0 || space.rlim_cur == RLIM_INFINITY)
    return SIZE_MAX;
  return static_cast<size_t>(space.rlim_cur);
}

} // namespace rt::platform
