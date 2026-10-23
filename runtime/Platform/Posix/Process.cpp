// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The process's environment, its id, waiting, the time, its end and the
// signals it ends by, and errno, on a POSIX system: Linux and macOS alike.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <errno.h>
#include <signal.h>
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

bool setEnvironment(const char *name, const char *value, WhenSet set) noexcept {
  return setenv(name, value, static_cast<int>(set)) == 0;
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

void ignoreBrokenPipes() noexcept { signal(SIGPIPE, SIG_IGN); }

// The signal's default action restored and the signal unblocked, then
// raised: the process ends by it, as a parent sees. abort() does all three
// for SIGABRT; it is also what follows raise(SIGPIPE), which the default
// action does not return from.
void raiseSignal(idr::endings::EndingSignal ending) noexcept {
  if (ending == idr::endings::EndingSignal::BrokenPipe) {
    signal(SIGPIPE, SIG_DFL);
    sigset_t pipe;
    sigemptyset(&pipe);
    sigaddset(&pipe, SIGPIPE);
    sigprocmask(SIG_UNBLOCK, &pipe, nullptr);
    raise(SIGPIPE);
  }
  signal(SIGABRT, SIG_DFL);
  abort();
}

} // namespace rt::platform
