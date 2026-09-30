// The features of an x86-64 processor, as compiler-rt reads them at
// startup: its cpuid test also asks the operating system whether it saves
// the AVX and AVX-512 registers, without which those features are unusable.
// PIN(runtime-quarantine) — see PINS.md

#include "platform.h"

#include "idris_rt.h"

namespace rt::platform {

[[clang::annotate("idris-rt-baseline")]] uint64_t cpuFeatures() noexcept {
  __builtin_cpu_init();
  uint64_t features = 0;
#define IDRIS_RT_CPU_TEST(bit, name)                                                             \
  if (__builtin_cpu_supports(name))                                                              \
    features |= uint64_t{1} << (bit);
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_TEST)
#undef IDRIS_RT_CPU_TEST
  return features;
}

} // namespace rt::platform
