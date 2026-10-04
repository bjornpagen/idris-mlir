// rt.platform:memory: address space, by the page, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <sys/mman.h>
#include <unistd.h>

export module rt.platform:memory;

export namespace rt::platform {

// The size of a page, which a guard and a region are multiples of: the
// target entry's (IDRIS_RT_PAGE_SIZE, CMakeLists.txt), a constant, so that
// rounding to it folds. checkPageSize below makes it the system's before
// anything uses it: the program's entry and the reserved-stack runner call
// it first.
constexpr size_t pageSize() noexcept { return IDRIS_RT_PAGE_SIZE; }

// The target entry's page size must be the system's, or every region, guard
// and alignment the runtime makes would use the wrong page, and so would
// snmalloc, whose page is the same number (rt.alloc:classes). The system's is
// sysconf's: the page of the process's address space, which mmap and
// mprotect round to (on Darwin, hw.pagesize and vm_page_size alike: 16 KiB
// for an arm64 process). When the two disagree it names both and ends the
// process, so a runtime built for another page size refuses to start. It
// allocates nothing and writes with write(2), not rt.io, which is above it.
// It runs before the processor test, so it stays compiled for the target's
// baseline (idris-rt-baseline), with no call that idris-mlir-cc could raise.
[[clang::annotate("idris-rt-baseline")]] void checkPageSize() noexcept {
  size_t system = static_cast<size_t>(sysconf(_SC_PAGESIZE));
  if (system == pageSize())
    return;
  static constexpr char built[] = "idris-mlir: the runtime is built for a ";
  static constexpr char has[] = "-byte page, and this system has a ";
  static constexpr char page[] = "-byte page\n";
  char message[sizeof built + sizeof has + sizeof page + 2 * 20];
  size_t n = 0;
  const char *parts[] = {built, nullptr, has, nullptr, page};
  size_t numbers[] = {pageSize(), system};
  size_t next = 0;
  for (const char *part : parts) {
    if (part != nullptr) {
      for (; *part != '\0'; ++part)
        message[n++] = *part;
      continue;
    }
    char digits[20];
    size_t d = 0;
    for (size_t value = numbers[next++]; d == 0 || value != 0; value /= 10)
      digits[d++] = static_cast<char>('0' + value % 10);
    while (d > 0)
      message[n++] = digits[--d];
  }
  for (size_t written = 0; written < n;) {
    ssize_t step = write(2, message + written, n - written);
    if (step <= 0)
      break;
    written += static_cast<size_t>(step);
  }
  _exit(IDRIS_RT_CRASHED);
}

// `size` bytes of address space, readable and writable and committed as
// they are touched, or null when the system grants none that large.
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

// Makes the n bytes at p, whole pages, inaccessible.
bool protect(char *p, size_t n) noexcept { return mprotect(p, n, PROT_NONE) == 0; }

// Gives the `size` bytes of address space at p back.
void release(char *p, size_t size) noexcept { munmap(p, size); }

} // namespace rt::platform
