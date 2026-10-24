// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The features of an AArch64 processor under Darwin, as function
// multiversioning tests them. There is no __builtin_cpu_init on AArch64,
// and compiler-rt starts the bits by an entry of each operating system's
// own: Darwin's reads them from sysctl in __init_cpu_features_resolver,
// which may be called any number of times. The bits themselves are
// cpuFeatureBits.
#include "Platform/CpuBits.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stdint.h>

extern "C" void __init_cpu_features_resolver(void) noexcept;

namespace rt::platform {

IDRIS_RT_BASELINE uint64_t cpuFeatures() noexcept {
  __init_cpu_features_resolver();
  return cpuFeatureBits();
}

} // namespace rt::platform
