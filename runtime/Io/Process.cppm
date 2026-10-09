// rt.io:process: base's process (System): its arguments, its environment,
// waiting, the time and its id.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stdint.h>
#include <string.h>

export module rt.io:process;

import rt.platform;
import rt.start;
import :errors;
import :handles;
import :scratch;

namespace {

// A string of the environment's, in the runtime's one environment slot,
// which the next environment call refills, or null.
int64_t environmentString(const char *text) {
  if (text == nullptr)
    return rt::io::nullHandle;
  rt::io::environmentHandle = rt::io::keepString(
      rt::io::environmentHandle, idris_rt_str_from_bytes(text, strlen(text)));
  return rt::io::environmentHandle;
}

} // namespace

// The number of the program's arguments, its own name the first.
extern "C" int64_t idris_rt_io_arg_count(void) { return rt::start::argumentCount(); }

// The program's argument at an index, a new string, decoded as any bytes
// from outside the program are; the empty string past the last.
extern "C" const idris_rt_str *idris_rt_io_arg(int64_t index) {
  return rt::start::argument(index);
}

// getenv's: the value of an environment variable, as a string handle the
// runtime owns, or null when it is not set.
extern "C" int64_t idris_rt_io_env_get(const idris_rt_str *name) {
  rt::io::Scratch text;
  return environmentString(rt::platform::environment(rt::io::cText(text, name)));
}

// The environment's `name=value` entry at an index, as a string handle the
// runtime owns, or null past the last (and before the first).
extern "C" int64_t idris_rt_io_env_pair(int64_t index) {
  return environmentString(rt::platform::environmentEntry(index));
}

// setenv's: sets an environment variable to a value, unless it is set and
// `overwrite` is 0; 0, or -1 when the name is not one a variable can have.
extern "C" int64_t idris_rt_io_env_set(const idris_rt_str *name, const idris_rt_str *value,
                                       int64_t overwrite) {
  rt::io::Scratch nameText;
  rt::io::Scratch valueText;
  if (rt::platform::setEnvironment(rt::io::cText(nameText, name), rt::io::cText(valueText, value),
                                   overwrite != 0))
    return 0;
  rt::io::saveError();
  return -1;
}

// unsetenv's: removes an environment variable, set or not; 0, or -1 when the
// name is not one a variable can have.
extern "C" int64_t idris_rt_io_env_unset(const idris_rt_str *name) {
  rt::io::Scratch text;
  if (rt::platform::unsetEnvironment(rt::io::cText(text, name)))
    return 0;
  rt::io::saveError();
  return -1;
}

// Waits a number of seconds, or until a signal cuts the wait short, as
// nanosleep does; pending output stays pending.
extern "C" void idris_rt_io_sleep(int64_t seconds) {
  if (!rt::platform::sleepFor(seconds, 0))
    rt::io::saveError();
}

// Waits a number of microseconds, as sleep does.
extern "C" void idris_rt_io_usleep(int64_t microseconds) {
  if (!rt::platform::sleepFor(microseconds / 1000000, microseconds % 1000000 * 1000))
    rt::io::saveError();
}

// time's: the seconds since the epoch, 00:00:00 UTC on 1 January 1970.
extern "C" int64_t idris_rt_io_time(void) { return rt::platform::secondsSinceEpoch(); }

// getpid's.
extern "C" int64_t idris_rt_io_pid(void) { return rt::platform::processId(); }
