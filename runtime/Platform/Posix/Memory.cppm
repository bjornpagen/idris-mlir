// rt.platform:memory: address space, by the page, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <sys/mman.h>
#include <unistd.h>

export module rt.platform:memory;

export namespace rt::platform {

// The size of a page, which a guard and a region are multiples of. It is the
// system's, read once; every other page-sized quantity is a multiple of this
// (Runner.cppm) or the target entry's one number (checkPageSize below).
size_t pageSize() noexcept { return static_cast<size_t>(sysconf(_SC_PAGESIZE)); }

// The page size the target entry names (IDRIS_RT_PAGE_SIZE, CMakeLists.txt)
// must be the system's, or every region, guard and alignment the runtime
// makes would use the wrong page. This runs at a program's entry, before
// anything reserves memory, and ends the process with a named error when the
// two disagree, so a runtime built for another page size refuses to start.
// It writes with write(2), not rt.io, which is above it.
void checkPageSize() noexcept {
  size_t system = pageSize();
  if (system == static_cast<size_t>(IDRIS_RT_PAGE_SIZE))
    return;
  char message[160];
  size_t n = 0;
  auto put = [&message, &n](const char *text) {
    for (; *text != '\0'; ++text)
      message[n++] = *text;
  };
  auto putNumber = [&message, &n](size_t value) {
    char digits[20];
    size_t d = 0;
    do {
      digits[d++] = static_cast<char>('0' + value % 10);
      value /= 10;
    } while (value != 0);
    while (d > 0)
      message[n++] = digits[--d];
  };
  put("idris-mlir: the runtime is built for a ");
  putNumber(static_cast<size_t>(IDRIS_RT_PAGE_SIZE));
  put("-byte page, and this system has a ");
  putNumber(system);
  put("-byte page\n");
  ssize_t ignored = write(2, message, n);
  static_cast<void>(ignored);
  _exit(IDRIS_RT_CRASHED);
}

// `size` bytes of address space, readable and writable and committed as
// they are touched, or null when the system grants none that large.
char *reserve(size_t size) noexcept {
  int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#ifdef MAP_NORESERVE
  // Linux would otherwise count the whole region against overcommit.
  flags |= MAP_NORESERVE;
#endif
  void *region = mmap(nullptr, size, PROT_READ | PROT_WRITE, flags, -1, 0);
  return region == MAP_FAILED ? nullptr : static_cast<char *>(region);
}

// Makes the n bytes at p, whole pages, inaccessible.
bool protect(char *p, size_t n) noexcept { return mprotect(p, n, PROT_NONE) == 0; }

// Gives the `size` bytes of address space at p back.
void release(char *p, size_t size) noexcept { munmap(p, size); }

} // namespace rt::platform
