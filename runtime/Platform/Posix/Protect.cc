// Inaccessible pages, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>
#include <sys/mman.h>

module rt.platform;

bool rt::platform::protect(char *p, size_t n) noexcept { return mprotect(p, n, PROT_NONE) == 0; }
