// rt.platform:cpu: the processor's features.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stdint.h>

export module rt.platform:cpu;

export namespace rt::platform {

// The IDRIS_RT_CPU_FEATURES bits of the features this processor has and
// the operating system supports. It is compiled for the target's baseline
// and kept there (the annotation idris-rt-baseline), since it runs before
// anything shows that the processor has more.
uint64_t cpuFeatures() noexcept;

} // namespace rt::platform
