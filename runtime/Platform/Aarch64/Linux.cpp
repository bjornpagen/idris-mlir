// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The features of an AArch64 processor under Linux, as function
// multiversioning tests them. There is no __builtin_cpu_init on AArch64,
// and compiler-rt starts the bits by an entry of each operating system's
// own: Linux's reads them from the kernel's hardware capabilities
// (getauxval) in __init_cpu_features, which compiler-rt's own constructor
// runs too and which may be called any number of times. The bits
// themselves are cpuFeatureBits.
#include "Platform/CpuBits.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stdint.h>

extern "C" void __init_cpu_features(void) noexcept;

namespace rt::platform {

IDRIS_RT_BASELINE uint64_t cpuFeatures() noexcept {
  __init_cpu_features();
  return cpuFeatureBits();
}

} // namespace rt::platform
