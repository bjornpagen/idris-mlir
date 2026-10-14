// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The system's clocks, through POSIX's clock_gettime, whose clock ids Linux
// and macOS both define.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"

#include <stdint.h>
#include <time.h>

namespace rt::platform {

bool readClock(Clock clock, int64_t &seconds, int64_t &nanoseconds) noexcept {
  clockid_t id = CLOCK_MONOTONIC;
  switch (clock) {
  case Clock::Monotonic:
    break;
  case Clock::Utc:
    id = CLOCK_REALTIME;
    break;
  case Clock::Process:
    id = CLOCK_PROCESS_CPUTIME_ID;
    break;
  case Clock::Thread:
    id = CLOCK_THREAD_CPUTIME_ID;
    break;
  }
  struct timespec reading {};
  if (clock_gettime(id, &reading) != 0)
    return false;
  seconds = static_cast<int64_t>(reading.tv_sec);
  nanoseconds = static_cast<int64_t>(reading.tv_nsec);
  return true;
}

} // namespace rt::platform
