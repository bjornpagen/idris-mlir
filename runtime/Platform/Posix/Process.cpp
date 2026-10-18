// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The process's environment, its id, waiting, the time, its end, and
// errno, on a POSIX system: Linux and macOS alike.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

// POSIX's environment, which every system of the target entries defines for
// an executable (on Darwin, libdyld's); not every C library declares it.
extern "C" char **environ;

namespace rt::platform {

int lastError() noexcept { return errno; }

const char *errorText(int code) noexcept { return strerror(code); }

const char *environment(const char *name) noexcept { return getenv(name); }

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

bool sleepFor(int64_t seconds, int64_t nanoseconds) noexcept {
  struct timespec span {};
  span.tv_sec = static_cast<time_t>(seconds);
  span.tv_nsec = static_cast<long>(nanoseconds);
  return nanosleep(&span, nullptr) == 0;
}

int64_t secondsSinceEpoch() noexcept { return static_cast<int64_t>(time(nullptr)); }

int64_t processId() noexcept { return static_cast<int64_t>(getpid()); }

IDRIS_RT_BASELINE void exitProcess(int status) noexcept { _exit(status); }

} // namespace rt::platform
