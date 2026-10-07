// rt.platform:cpu: the features of an AArch64 processor, as function
// multiversioning tests them. There is no __builtin_cpu_init on AArch64.
// Where compiler-rt fills the bits in a static constructor, this calls
// nothing first; where it reads them only when a function asks (Apple's,
// from sysctl), it calls the function the target entry names
// (IDRIS_RT_CPU_FEATURES_INIT), which may be called any number of times.
// The bits themselves are cpuFeatureBits.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "Platform/CpuBits.h"

#ifdef IDRIS_RT_CPU_FEATURES_INIT
extern "C" void IDRIS_RT_CPU_FEATURES_INIT(void) noexcept;
#endif

export module rt.platform:cpu;

export namespace rt::platform {

// The IDRIS_RT_CPU_FEATURES bits of the features this processor has and
// the operating system supports. It is compiled for the target's baseline
// and kept there (the annotation idris-rt-baseline), since it runs before
// anything shows that the processor has more.
[[clang::annotate("idris-rt-baseline")]] uint64_t cpuFeatures() noexcept {
#ifdef IDRIS_RT_CPU_FEATURES_INIT
  IDRIS_RT_CPU_FEATURES_INIT();
#endif
  return cpuFeatureBits();
}

} // namespace rt::platform
