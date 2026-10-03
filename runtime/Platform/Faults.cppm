// rt.platform:faults: catching a fault on memory.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stdint.h>

export module rt.platform:faults;

export namespace rt::platform {

// From now on a fault on memory calls onFault with the faulting address, on
// the thread's signal stack; when onFault returns, the fault gets the action
// it had before this call, as if it were never caught. onFault may only make
// async-signal-safe calls. The first call installs it, and later ones
// replace onFault.
void catchFaults(void (*onFault)(uintptr_t address)) noexcept;

} // namespace rt::platform
