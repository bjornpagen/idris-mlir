// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Base's clocks (System.Clock): one reading per kind of clock, each an
// instance of one function over the kind. A reading is an immediate value,
// seconds shifted past the nanoseconds, or the mark of a clock that could
// not be read (the specification's encoding, IdrisMLIR.Spec.Runtime.Clocks),
// so reading a clock allocates nothing and leaves nothing to free, and
// taking one apart is arithmetic the compiler writes, with no call.
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stdint.h>

namespace {

// The clock's reading, or the mark when the system cannot read it (errno
// saved) or its seconds are outside what a reading holds: before the
// epoch, or from the year 2242 on.
template <idr::clocks::ClockKind K>
int64_t reading() {
  int64_t seconds = 0;
  int64_t nanoseconds = 0;
  if (!rt::platform::readClock(K, seconds, nanoseconds)) {
    rt::io::saveError();
    return idr::clocks::unreadable;
  }
  if (seconds < 0 || seconds >= int64_t{1} << idr::clocks::secondsBits)
    return idr::clocks::unreadable;
  return seconds << idr::clocks::nanosecondBits | nanoseconds;
}

} // namespace

// The time since some point in the past, which never runs backwards; the
// time since the epoch, 00:00:00 UTC on 1 January 1970; the CPU time the
// process has used; the CPU time the calling thread has used.
extern "C" int64_t idris_rt_io_clock_monotonic(void) {
  return reading<idr::clocks::ClockKind::Monotonic>();
}
extern "C" int64_t idris_rt_io_clock_utc(void) { return reading<idr::clocks::ClockKind::Utc>(); }
extern "C" int64_t idris_rt_io_clock_process(void) {
  return reading<idr::clocks::ClockKind::Process>();
}
extern "C" int64_t idris_rt_io_clock_thread(void) {
  return reading<idr::clocks::ClockKind::Thread>();
}
