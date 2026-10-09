// rt.platform:clocks: the system's clocks, through POSIX's clock_gettime,
// whose clock ids Linux and macOS both define.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stdint.h>
#include <time.h>

export module rt.platform:clocks;

export namespace rt::platform {

// The clocks base's ClockType names: the time since some point in the past,
// the time since the epoch, and the CPU time of the process and of the
// calling thread.
enum class Clock { Monotonic, Utc, Process, Thread };

// The clock's reading; false when the system cannot read it.
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
