// The size of a page, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>
#include <unistd.h>

module rt.platform;

size_t rt::platform::pageSize() noexcept { return static_cast<size_t>(sysconf(_SC_PAGESIZE)); }
