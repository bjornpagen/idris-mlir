// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one simdutf implementation the runtime calls: the one the target's
// entry fixes (IDRIS_RT_SIMDUTF_HEADER and IDRIS_RT_SIMDUTF_CLASS,
// runtime/CMakeLists.txt), the only one simdutf is built with. It is called
// through its own class, which is final, so every call into simdutf is a
// direct call: nothing is chosen at run time, no processor is asked, and the
// stack bound sees each call's callee. A machine that lacks what its
// kernels use is refused by the startup check, as one that lacks what the
// program uses is (rt::start::checkMachine).
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include IDRIS_RT_SIMDUTF_HEADER

#include <type_traits>

namespace rt::strings {

using Utf8 = IDRIS_RT_SIMDUTF_CLASS;

static_assert(std::is_final_v<Utf8>,
              "a call through the implementation's class is direct only when it is final");

// A constant: its constructor only names the implementation, so it is
// initialized when the program is built and never at run time.
inline constexpr Utf8 utf8{};

} // namespace rt::strings
