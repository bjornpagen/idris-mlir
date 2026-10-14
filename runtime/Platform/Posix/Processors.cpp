// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How many processors are online, read when asked.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"

#include <stdint.h>
#include <unistd.h>

namespace rt::platform {

int64_t nprocessors() noexcept {
  return static_cast<int64_t>(sysconf(_SC_NPROCESSORS_ONLN));
}

} // namespace rt::platform
