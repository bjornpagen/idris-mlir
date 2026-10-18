// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The target's user address space, the target entry's fact
// (IDRIS_MLIR_USER_ADDRESS_BITS, CMakeLists.txt). Only the units that read it
// include this, so the others compile without its definition.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

namespace rt::platform {

// The bits of the highest address user space reaches: no address the
// program sees, a stack cell's or its stack's, has more.
inline constexpr unsigned userAddressBits = IDRIS_RT_USER_ADDRESS_BITS;

} // namespace rt::platform
