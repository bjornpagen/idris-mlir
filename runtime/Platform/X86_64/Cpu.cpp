// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The features of an x86-64 processor. The bits are cpuFeatureBits; this
// entry's startup is __builtin_cpu_init, which also asks the operating
// system whether it saves the AVX and AVX-512 registers, without which those
// features are unusable.
// PIN(runtime-quarantine), PIN(simdutf-dispatch) — see PINS.md
#include "Platform/CpuBits.h"
#include "Platform/Platform.h"

#include <stdint.h>

#include <string_view>

namespace rt::platform {

[[clang::annotate("idris-rt-baseline")]] uint64_t cpuFeatures() noexcept {
  __builtin_cpu_init();
  return cpuFeatureBits();
}

// simdutf's x86-64 implementations, best first, each tested for exactly the
// features of the target region its kernels are compiled in
// (src/simdutf/<name>.h): icelake's includes AVX512VPOPCNTDQ, which
// simdutf's own test cannot see, haswell's LZCNT and POPCNT, westmere's
// POPCNT. The fallback runs anywhere.
bool runsSimdutf(std::string_view name) noexcept {
  __builtin_cpu_init();
  if (name == "icelake")
    return __builtin_cpu_supports("avx512f") && __builtin_cpu_supports("avx512dq") &&
           __builtin_cpu_supports("avx512cd") && __builtin_cpu_supports("avx512bw") &&
           __builtin_cpu_supports("avx512vbmi") && __builtin_cpu_supports("avx512vbmi2") &&
           __builtin_cpu_supports("avx512vl") && __builtin_cpu_supports("avx2") &&
           __builtin_cpu_supports("bmi") && __builtin_cpu_supports("bmi2") &&
           __builtin_cpu_supports("pclmul") && __builtin_cpu_supports("lzcnt") &&
           __builtin_cpu_supports("popcnt") && __builtin_cpu_supports("avx512vpopcntdq");
  if (name == "haswell")
    return __builtin_cpu_supports("avx2") && __builtin_cpu_supports("bmi") &&
           __builtin_cpu_supports("lzcnt") && __builtin_cpu_supports("popcnt");
  if (name == "westmere")
    return __builtin_cpu_supports("sse4.2") && __builtin_cpu_supports("popcnt");
  return name == "fallback";
}

} // namespace rt::platform
