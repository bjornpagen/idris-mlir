// The features of an AArch64 processor, as function multiversioning tests
// them. There is no __builtin_cpu_init on AArch64: Apple's compiler-rt reads
// the bits from sysctl only when a function asks, in
// __init_cpu_features_resolver, which may be called any number of times.
// The bits themselves are cpuFeatureBits.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/CpuBits.h"
#include "Platform/Platform.h"

#include <stdint.h>

extern "C" void __init_cpu_features_resolver(void) noexcept;

namespace rt::platform {

[[clang::annotate("idris-rt-baseline")]] uint64_t cpuFeatures() noexcept {
  __init_cpu_features_resolver();
  return cpuFeatureBits();
}

} // namespace rt::platform
