// Address space, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>
#include <sys/mman.h>

module rt.platform;

char *rt::platform::reserve(size_t size) noexcept {
  int flags = MAP_PRIVATE | MAP_ANONYMOUS;
#ifdef MAP_NORESERVE
  // Linux would otherwise count the whole region against overcommit.
  flags |= MAP_NORESERVE;
#endif
  void *region = mmap(nullptr, size, PROT_READ | PROT_WRITE, flags, -1, 0);
  return region == MAP_FAILED ? nullptr : static_cast<char *>(region);
}
