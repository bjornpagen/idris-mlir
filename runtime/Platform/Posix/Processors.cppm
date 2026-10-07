// rt.platform:processors: how many processors are online, read when asked.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stdint.h>
#include <unistd.h>

export module rt.platform:processors;

export namespace rt::platform {

// The number of processors online, from the system, at the moment it is
// asked. -1 when the system does not say.
int64_t nprocessors() noexcept {
  return static_cast<int64_t>(sysconf(_SC_NPROCESSORS_ONLN));
}

} // namespace rt::platform
