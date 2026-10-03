// rt.platform:memory: address space, by the page, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>
#include <sys/mman.h>
#include <unistd.h>

export module rt.platform:memory;

export namespace rt::platform {

// The size of a page, which a guard and a region are multiples of.
size_t pageSize() noexcept { return static_cast<size_t>(sysconf(_SC_PAGESIZE)); }

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
