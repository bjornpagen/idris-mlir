// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The system's clocks, through POSIX's clock_gettime, whose clock ids Linux
// and macOS both define.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"

#include <stddef.h>
#include <stdint.h>
#include <time.h>

namespace {

// Each kind's clock id, at the kind's position in the specification's list.
constexpr clockid_t clockIds[] = {CLOCK_MONOTONIC, CLOCK_REALTIME, CLOCK_PROCESS_CPUTIME_ID,
                                  CLOCK_THREAD_CPUTIME_ID};
static_assert(static_cast<size_t>(idr::clocks::ClockKind::Monotonic) == 0 &&
              static_cast<size_t>(idr::clocks::ClockKind::Utc) == 1 &&
              static_cast<size_t>(idr::clocks::ClockKind::Process) == 2 &&
              static_cast<size_t>(idr::clocks::ClockKind::Thread) == 3 &&
              sizeof clockIds / sizeof clockIds[0] == 4,
              "one clock id per kind, in the kinds' order");

} // namespace

namespace rt::platform {

bool readClock(idr::clocks::ClockKind clock, int64_t &seconds, int64_t &nanoseconds) noexcept {
  struct timespec reading {};
  if (clock_gettime(clockIds[static_cast<size_t>(clock)], &reading) != 0)
    return false;
  seconds = static_cast<int64_t>(reading.tv_sec);
  nanoseconds = static_cast<int64_t>(reading.tv_nsec);
  return true;
}

} // namespace rt::platform
