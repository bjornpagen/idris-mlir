// Address space given back, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>
#include <sys/mman.h>

module rt.platform;

void rt::platform::release(char *p, size_t size) noexcept { munmap(p, size); }
