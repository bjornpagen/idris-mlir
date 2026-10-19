// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The processor features a program may be compiled to use and
// idris_rt_start tests: the target entry's list (CMakeLists.txt), the
// header IDRIS_RT_CPU_FEATURES_FILE names. Each is X(bit, test, name):
// `test` is what __builtin_cpu_supports tests at the program's entry, and
// `name` what LLVM calls the same feature, which idr-entry asks the
// module's target's machine for to set the bit. Where the two name spaces
// differ (AArch64's), the entry gives both.
// PIN(runtime-quarantine) — see PINS.md

#pragma once

#ifndef IDRIS_RT_CPU_FEATURES_FILE
#error "the target entry names the list of processor features (IDRIS_RT_CPU_FEATURES_FILE)"
#endif

#include IDRIS_RT_CPU_FEATURES_FILE
