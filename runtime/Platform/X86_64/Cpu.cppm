// rt.platform:cpu: the features of an x86-64 processor, as compiler-rt reads
// them at startup: its cpuid test also asks the operating system whether it
// saves the AVX and AVX-512 registers, without which those features are
// unusable.
// PIN(runtime-quarantine) — see PINS.md
module;
// The target entry's list of features, an X-macro, which no import carries.
#include "cpu_features.h"

#include <stdint.h>

export module rt.platform:cpu;

export namespace rt::platform {

// The IDRIS_RT_CPU_FEATURES bits of the features this processor has and
// the operating system supports. It is compiled for the target's baseline
// and kept there (the annotation idris-rt-baseline), since it runs before
// anything shows that the processor has more.
[[clang::annotate("idris-rt-baseline")]] uint64_t cpuFeatures() noexcept {
  __builtin_cpu_init();
  uint64_t features = 0;
#define IDRIS_RT_CPU_TEST(bit, test, name)                                                       \
  if (__builtin_cpu_supports(test))                                                              \
    features |= uint64_t{1} << (bit);
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_TEST)
#undef IDRIS_RT_CPU_TEST
  return features;
}

} // namespace rt::platform
