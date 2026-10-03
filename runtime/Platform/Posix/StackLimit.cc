// The process's stack limit, on a POSIX system.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>
#include <stdint.h>
#include <sys/resource.h>

module rt.platform;

size_t rt::platform::stackLimit() noexcept {
  rlimit limit{};
  if (getrlimit(RLIMIT_STACK, &limit) != 0)
    return 0;
  return limit.rlim_cur == RLIM_INFINITY ? SIZE_MAX : static_cast<size_t>(limit.rlim_cur);
}
