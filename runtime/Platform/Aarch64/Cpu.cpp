// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The features of an AArch64 processor, as function multiversioning tests
// them. There is no __builtin_cpu_init on AArch64: compiler-rt reads the
// bits when a function asks, Apple's from sysctl in
// __init_cpu_features_resolver, and on Linux from the kernel's hardware
// capabilities (getauxval) in __init_cpu_features, which compiler-rt's own
// constructor runs too; either may be called any number of times. The bits
// themselves are cpuFeatureBits.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/CpuBits.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stdint.h>

#if defined(__APPLE__)
extern "C" void __init_cpu_features_resolver(void) noexcept;
#else
extern "C" void __init_cpu_features(void) noexcept;
#endif

namespace rt::platform {

IDRIS_RT_BASELINE uint64_t cpuFeatures() noexcept {
#if defined(__APPLE__)
  __init_cpu_features_resolver();
#else
  __init_cpu_features();
#endif
  return cpuFeatureBits();
}

} // namespace rt::platform
