// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Address space, by the page, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <unistd.h>

namespace {

// The check's text, built inline into it so that nothing it calls leaves
// the baseline.
[[gnu::always_inline]] inline char *text(char *at, const char *part) {
  while (*part != '\0')
    *at++ = *part++;
  return at;
}

[[gnu::always_inline]] inline char *number(char *at, size_t value) {
  char digits[20];
  size_t d = 0;
  do {
    digits[d++] = static_cast<char>('0' + value % 10);
    value /= 10;
  } while (value != 0);
  while (d > 0)
    *at++ = digits[--d];
  return at;
}

} // namespace

namespace rt::platform {

// The target entry's page size must be the system's, or every region, guard
// and alignment the runtime makes would use the wrong page, and so would
// snmalloc, whose page is the same number (Alloc/Cells.cpp). The system's is
// sysconf's: the page of the process's address space, which mmap and
// mprotect round to (on Darwin, hw.pagesize and vm_page_size alike: 16 KiB
// for an arm64 process). When the two disagree it names both and ends the
// process, so a runtime built for another page size refuses to start. It
// allocates nothing and writes with writeAll, not rt::io, which is above
// it. It runs before the processor test, so it and what it calls stay
// compiled for the target's baseline: its text is built inline, and
// writeAll and exitProcess are marked as it is.
[[clang::annotate("idris-rt-baseline")]] void checkPageSize() noexcept {
  size_t system = static_cast<size_t>(sysconf(_SC_PAGESIZE));
  if (system == pageSize())
    return;
  static constexpr char built[] = "idris-mlir: the runtime is built for a ";
  static constexpr char has[] = "-byte page, and this system has a ";
  static constexpr char page[] = "-byte page\n";
  char message[sizeof built + sizeof has + sizeof page + 2 * 20];
  char *at = text(message, built);
  at = number(at, pageSize());
  at = text(at, has);
  at = number(at, system);
  at = text(at, page);
  writeAll(2, message, static_cast<size_t>(at - message));
  exitProcess(IDRIS_RT_CRASHED);
}

char *reserve(size_t size) noexcept {
  int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#ifdef MAP_NORESERVE
  // Linux would otherwise count the whole region against overcommit. Darwin
  // defines the flag and ignores it: it never counts a reservation, and
  // grants 2^46 bytes of address space either way.
  flags |= MAP_NORESERVE;
#endif
  void *region = mmap(nullptr, size, PROT_READ | PROT_WRITE, flags, -1, 0);
  return region == MAP_FAILED ? nullptr : static_cast<char *>(region);
}

bool protect(char *p, size_t n) noexcept { return mprotect(p, n, PROT_NONE) == 0; }

void release(char *p, size_t size) noexcept { munmap(p, size); }

} // namespace rt::platform
