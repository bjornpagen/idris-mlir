// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The processor features a program may be compiled to use and the startup
// check tests: the target entry's list (CMakeLists.txt), the
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

#ifdef __cplusplus
#include <stddef.h>
#include <stdint.h>

#include <string_view>

namespace rt::platform {

// The bits of the list's features that a list of LLVM features enables, as
// a function's "target-features" spells it ("+avx2,+bmi,-avx512f"), where a
// later item overrides an earlier one, as LLVM reads it. The CPU programs
// are compiled for is such a list in the target's entry, so the bits a
// processor must have to run what the target's programs and tools run are a
// constant of the build, never a question asked of a machine.
consteval uint64_t featureBitsOf(std::string_view features) {
  auto enabled = [features](std::string_view name) {
    bool on = false;
    for (std::string_view rest = features; !rest.empty();) {
      size_t comma = rest.find(',');
      std::string_view item = rest.substr(0, comma);
      if (item.size() == name.size() + 1 && item.substr(1) == name)
        on = item[0] == '+';
      if (comma == std::string_view::npos)
        break;
      rest.remove_prefix(comma + 1);
    }
    return on;
  };
  uint64_t bits = 0;
#define IDRIS_RT_CPU_ENABLED(bit, test, name)                                                    \
  if (enabled(name))                                                                             \
    bits |= uint64_t{1} << (bit);
  IDRIS_RT_CPU_FEATURES(IDRIS_RT_CPU_ENABLED)
#undef IDRIS_RT_CPU_ENABLED
  return bits;
}

} // namespace rt::platform
#endif
