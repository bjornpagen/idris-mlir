// rt.platform:cpu: the features of an AArch64 processor, as function
// multiversioning tests them. There is no __builtin_cpu_init on AArch64:
// Apple's compiler-rt reads the bits from sysctl only when a function asks,
// in __init_cpu_features_resolver, which may be called any number of times.
// The bits themselves are cpuFeatureBits.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stdint.h>

extern "C" void __init_cpu_features_resolver(void) noexcept;

export module rt.platform:cpu;

import :cpubits;

export namespace rt::platform {

// The IDRIS_RT_CPU_FEATURES bits of the features this processor has and
// the operating system supports. It is compiled for the target's baseline
// and kept there (the annotation idris-rt-baseline), since it runs before
// anything shows that the processor has more.
[[clang::annotate("idris-rt-baseline")]] uint64_t cpuFeatures() noexcept {
  __init_cpu_features_resolver();
  return cpuFeatureBits();
}

} // namespace rt::platform
