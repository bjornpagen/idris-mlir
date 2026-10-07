// rt.platform:cpu: the features of an x86-64 processor. The bits are
// cpuFeatureBits; this entry's startup is __builtin_cpu_init, which also
// asks the operating system whether it saves the AVX and AVX-512 registers,
// without which those features are unusable.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "Platform/CpuBits.h"

export module rt.platform:cpu;

export namespace rt::platform {

// The IDRIS_RT_CPU_FEATURES bits of the features this processor has and
// the operating system supports. It is compiled for the target's baseline
// and kept there (the annotation idris-rt-baseline), since it runs before
// anything shows that the processor has more.
[[clang::annotate("idris-rt-baseline")]] uint64_t cpuFeatures() noexcept {
  __builtin_cpu_init();
  return cpuFeatureBits();
}

} // namespace rt::platform
