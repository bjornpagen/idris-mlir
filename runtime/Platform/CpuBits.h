// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The bits of IDRIS_RT_CPU_FEATURES the processor state already holds. Every
// processor startup file reads them here, after its own startup. The
// startup is the target difference; the bits are not.
#pragma once

#include "cpu_features.h"
#include "idris_rt.h"

#include <stdint.h>

namespace rt::platform {

// Compiled for the target's baseline, and kept there: it runs from the
// processor test, before anything shows that the processor has more. Inlined
// into that test, which is marked the same way, so the read cannot be split
// out and raised.
[[gnu::always_inline]] IDRIS_RT_BASELINE inline uint64_t cpuFeatureBits() noexcept {
  uint64_t features = 0;
#define IDRIS_RT_CPU_TEST(bit, test, name)                                                       \
  if (__builtin_cpu_supports(test))                                                              \
    features |= uint64_t{1} << (bit);
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_TEST)
#undef IDRIS_RT_CPU_TEST
  return features;
}

} // namespace rt::platform
