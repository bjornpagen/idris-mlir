// The processor features an x86-64 program may be compiled to use and
// idris_rt_start tests (cpu_features.h): those of the microarchitecture
// levels v2, v3 and v4 above the baseline. On x86-64 the name
// __builtin_cpu_supports tests and LLVM's are the same. A larger CPU may
// enable more, which are not tested.
// PIN(runtime-quarantine) — see PINS.md

#pragma once

#define IDRIS_RT_CPU_FEATURES(X)                                                                 \
  X(0, "cx16", "cx16")                                                                           \
  X(1, "popcnt", "popcnt")                                                                       \
  X(2, "sse3", "sse3")                                                                           \
  X(3, "sse4.1", "sse4.1")                                                                       \
  X(4, "sse4.2", "sse4.2")                                                                       \
  X(5, "ssse3", "ssse3")                                                                         \
  X(6, "sahf", "sahf")                                                                           \
  X(7, "avx", "avx")                                                                             \
  X(8, "avx2", "avx2")                                                                           \
  X(9, "bmi", "bmi")                                                                             \
  X(10, "bmi2", "bmi2")                                                                          \
  X(11, "f16c", "f16c")                                                                          \
  X(12, "fma", "fma")                                                                            \
  X(13, "lzcnt", "lzcnt")                                                                        \
  X(14, "movbe", "movbe")                                                                        \
  X(15, "xsave", "xsave")                                                                        \
  X(16, "avx512f", "avx512f")                                                                    \
  X(17, "avx512bw", "avx512bw")                                                                  \
  X(18, "avx512cd", "avx512cd")                                                                  \
  X(19, "avx512dq", "avx512dq")                                                                  \
  X(20, "avx512vl", "avx512vl")
