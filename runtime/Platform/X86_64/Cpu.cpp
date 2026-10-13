// The features of an x86-64 processor. The bits are cpuFeatureBits; this
// entry's startup is __builtin_cpu_init, which also asks the operating
// system whether it saves the AVX and AVX-512 registers, without which those
// features are unusable.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/CpuBits.h"
#include "Platform/Platform.h"

#include <stdint.h>

namespace rt::platform {

[[clang::annotate("idris-rt-baseline")]] uint64_t cpuFeatures() noexcept {
  __builtin_cpu_init();
  return cpuFeatureBits();
}

} // namespace rt::platform
