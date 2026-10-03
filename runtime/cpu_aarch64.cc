// The features of an AArch64 processor, as compiler-rt reads them for
// function multiversioning, which __builtin_cpu_supports tests: clang has no
// __builtin_cpu_init on AArch64. Where compiler-rt reads them in a static
// constructor (Linux's hardware capabilities), they are there before main;
// Apple's compiler-rt reads them (from sysctl) only when a function asks, in
// the function the target entry names (IDRIS_RT_CPU_FEATURES_INIT), which
// may be called any number of times.
// PIN(runtime-quarantine) — see PINS.md

#include "cpu_features.h"
#include "platform.h"

#ifdef IDRIS_RT_CPU_FEATURES_INIT
extern "C" void IDRIS_RT_CPU_FEATURES_INIT(void) noexcept;
#endif

namespace rt::platform {

[[clang::annotate("idris-rt-baseline")]] uint64_t cpuFeatures() noexcept {
#ifdef IDRIS_RT_CPU_FEATURES_INIT
  IDRIS_RT_CPU_FEATURES_INIT();
#endif
  uint64_t features = 0;
#define IDRIS_RT_CPU_TEST(bit, test, name)                                                       \
  if (__builtin_cpu_supports(test))                                                              \
    features |= uint64_t{1} << (bit);
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_TEST)
#undef IDRIS_RT_CPU_TEST
  return features;
}

} // namespace rt::platform
