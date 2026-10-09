// rt.platform:process: the process's environment, its id, waiting, the
// time, its end, and errno, on a POSIX system: Linux and macOS alike.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

// POSIX's environment, which every system of the target entries defines for
// an executable (on Darwin, libdyld's); not every C library declares it.
extern "C" char **environ;

export module rt.platform:process;

export namespace rt::platform {

// What the last failing call of the C library left in errno.
int lastError() noexcept { return errno; }

// strerror's text of an error number, valid until the next call.
const char *errorText(int code) noexcept { return strerror(code); }

// The value of an environment variable, valid until the environment
// changes, or null when it is not set.
const char *environment(const char *name) noexcept { return getenv(name); }

// The environment's `name=value` entry at an index, valid until the
// environment changes, or null when there is none.
const char *environmentEntry(int64_t index) noexcept {
  if (index < 0 || environ == nullptr)
    return nullptr;
  for (int64_t i = 0; i < index; ++i)
    if (environ[i] == nullptr)
      return nullptr;
  return environ[index];
}

bool setEnvironment(const char *name, const char *value, bool overwrite) noexcept {
  return setenv(name, value, overwrite ? 1 : 0) == 0;
}

bool unsetEnvironment(const char *name) noexcept { return unsetenv(name) == 0; }

// Waits that long, or until a signal interrupts the wait; false when it was
// cut short or the time is not one nanosleep takes.
bool sleepFor(int64_t seconds, int64_t nanoseconds) noexcept {
  struct timespec span {};
  span.tv_sec = static_cast<time_t>(seconds);
  span.tv_nsec = static_cast<long>(nanoseconds);
  return nanosleep(&span, nullptr) == 0;
}

int64_t secondsSinceEpoch() noexcept { return static_cast<int64_t>(time(nullptr)); }

int64_t processId() noexcept { return static_cast<int64_t>(getpid()); }

// Ends the process with the status at once: no handler runs and no stream of
// the C library is written.
[[noreturn]] void exitProcess(int status) noexcept { _exit(status); }

} // namespace rt::platform
