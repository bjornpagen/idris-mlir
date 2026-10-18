// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The features of an AArch64 processor, as function multiversioning tests
// them. There is no __builtin_cpu_init on AArch64: Apple's compiler-rt reads
// the bits from sysctl only when a function asks, in
// __init_cpu_features_resolver, which may be called any number of times.
// The bits themselves are cpuFeatureBits.
// PIN(runtime-quarantine), PIN(simdutf-dispatch) — see PINS.md
#include "Platform/CpuBits.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stdint.h>

#include <string_view>

extern "C" void __init_cpu_features_resolver(void) noexcept;

namespace rt::platform {

IDRIS_RT_BASELINE uint64_t cpuFeatures() noexcept {
  __init_cpu_features_resolver();
  return cpuFeatureBits();
}

// simdutf's one AArch64 implementation, arm64, is compiled for NEON, which
// every AArch64 processor has: the baseline runs it, with nothing to test.
bool runsSimdutf(std::string_view name) noexcept { return name == "arm64"; }

} // namespace rt::platform
