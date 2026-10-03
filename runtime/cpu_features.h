// The processor features a program may be compiled to use and
// idris_rt_start tests: the target entry's list (CMakeLists.txt), the
// header IDRIS_RT_CPU_FEATURES_FILE names. Each is X(bit, test, name):
// `test` is what __builtin_cpu_supports tests at the program's entry, and
// `name` what LLVM calls the same feature, which idr-lower looks for in the
// module's target to set the bit and idris-mlir-cc in the CPU the prepared
// runtime was compiled for. Where the two name spaces differ (AArch64's),
// the entry gives both.
// PIN(runtime-quarantine) — see PINS.md

#pragma once

#ifndef IDRIS_RT_CPU_FEATURES_FILE
#error "the target entry names the list of processor features (IDRIS_RT_CPU_FEATURES_FILE)"
#endif

#include IDRIS_RT_CPU_FEATURES_FILE
