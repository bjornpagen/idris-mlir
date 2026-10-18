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

// A number's decimal digits, written backwards from the end of `digits`,
// which has room for the 20 of the largest size_t; inline in the check, so
// that nothing it calls leaves the baseline.
[[gnu::always_inline]] inline rt::platform::Piece number(char (&digits)[20], size_t value) {
  char *end = digits + sizeof digits;
  char *at = end;
  do {
    *--at = static_cast<char>('0' + value % 10);
    value /= 10;
  } while (value != 0);
  return {at, static_cast<size_t>(end - at)};
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
// allocates nothing and writes with writeCrash, not rt::io, which is above
// it. It runs before the processor test, so it and what it calls stay
// compiled for the target's baseline: its digits are written inline, and
// writeCrash and exitProcess are marked as it is.
IDRIS_RT_BASELINE void checkPageSize() noexcept {
  size_t system = static_cast<size_t>(sysconf(_SC_PAGESIZE));
  if (system == pageSize())
    return;
  static constexpr char built[] = "the runtime is built for a ";
  static constexpr char has[] = "-byte page, and this system has a ";
  static constexpr char page[] = "-byte page";
  char builtDigits[20];
  char systemDigits[20];
  const Piece cause[] = {{built, sizeof built - 1},
                         number(builtDigits, pageSize()),
                         {has, sizeof has - 1},
                         number(systemDigits, system),
                         {page, sizeof page - 1}};
  writeCrash(cause, sizeof cause / sizeof cause[0]);
  exitProcess(IDRIS_RT_CRASHED);
}

// mmap gives a page's alignment. A larger one is a region `alignment - page`
// bytes longer, cut to the aligned part: what lies before and after it is
// given back, so only the aligned `size` bytes stay reserved. For a page's
// alignment nothing is added and nothing cut.
char *reserve(size_t size, size_t alignment) noexcept {
  int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#ifdef MAP_NORESERVE
  // Linux would otherwise count the whole region against overcommit. Darwin
  // defines the flag and ignores it: it never counts a reservation, and
  // grants 2^46 bytes of address space either way.
  flags |= MAP_NORESERVE;
#endif
  size_t extra = alignment - pageSize();
  void *region = mmap(nullptr, size + extra, PROT_READ | PROT_WRITE, flags, -1, 0);
  if (region == MAP_FAILED)
    return nullptr;
  char *start = static_cast<char *>(region);
  size_t before = roundUp(reinterpret_cast<uintptr_t>(start), alignment) -
                  reinterpret_cast<uintptr_t>(start);
  if (before != 0)
    release(start, before);
  if (extra != before)
    release(start + before + size, extra - before);
  return start + before;
}

bool protect(char *p, size_t n) noexcept { return mprotect(p, n, PROT_NONE) == 0; }

void release(char *p, size_t size) noexcept { munmap(p, size); }

} // namespace rt::platform
