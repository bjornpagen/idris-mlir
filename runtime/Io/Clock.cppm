// rt.io:clock: base's clocks (System.Clock). An OSClock is an immediate
// value, seconds << 30 | nanoseconds, so reading a clock allocates nothing
// and leaves nothing to free. Nanoseconds fit 30 bits, and seconds below 2^33
// keep the value positive, so -1 is free to mean a clock that is not valid.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>

export module rt.io:clock;

import rt.platform;
import :errors;

namespace {

constexpr int nanosecondBits = 30;
constexpr int64_t secondsLimit = int64_t{1} << 33;
constexpr int64_t invalid = -1;

// The clock's reading as an OSClock, or invalid when the system cannot read
// it (errno saved) or its seconds are outside what the value holds: before
// the epoch, or from the year 2242 on.
int64_t reading(rt::platform::Clock clock) {
  int64_t seconds = 0;
  int64_t nanoseconds = 0;
  if (!rt::platform::readClock(clock, seconds, nanoseconds)) {
    rt::io::saveError();
    return invalid;
  }
  if (seconds < 0 || seconds >= secondsLimit)
    return invalid;
  return seconds << nanosecondBits | nanoseconds;
}

} // namespace

// The time since some point in the past, which never runs backwards:
// CLOCK_MONOTONIC.
extern "C" int64_t idris_rt_io_clock_monotonic(void) {
  return reading(rt::platform::Clock::Monotonic);
}

// The time since the epoch, 00:00:00 UTC on 1 January 1970: CLOCK_REALTIME.
extern "C" int64_t idris_rt_io_clock_utc(void) { return reading(rt::platform::Clock::Utc); }

// The CPU time the process has used: CLOCK_PROCESS_CPUTIME_ID.
extern "C" int64_t idris_rt_io_clock_process(void) {
  return reading(rt::platform::Clock::Process);
}

// The CPU time the calling thread has used: CLOCK_THREAD_CPUTIME_ID.
extern "C" int64_t idris_rt_io_clock_thread(void) { return reading(rt::platform::Clock::Thread); }

// The time a collector has taken is never valid: no collector runs, memory
// is counted and freed as the program goes. Base makes both clocks optional,
// so clockTime GCCPU and clockTime GCReal give Nothing.
extern "C" int64_t idris_rt_io_clock_gc_cpu(void) { return invalid; }
extern "C" int64_t idris_rt_io_clock_gc_real(void) { return invalid; }

// 1 when an OSClock is valid, else 0.
extern "C" int64_t idris_rt_io_clock_valid(int64_t clock) { return clock >= 0 ? 1 : 0; }

// The seconds of an OSClock; 0 for one that is not valid.
extern "C" int64_t idris_rt_io_clock_second(int64_t clock) {
  return clock >= 0 ? clock >> nanosecondBits : 0;
}

// The nanoseconds of an OSClock, below 10^9; 0 for one that is not valid.
extern "C" int64_t idris_rt_io_clock_nanosecond(int64_t clock) {
  return clock >= 0 ? clock & ((int64_t{1} << nanosecondBits) - 1) : 0;
}
