// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A file's times (System.File.Meta's fileTime): read at once, as the one
// call of the system gives them, into the places its caller passes.
// PIN(runtime-quarantine) — see PINS.md
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stdint.h>

// The access, modification and status change times of the file the handle's
// stream names, as fstat gives them, each in seconds and nanoseconds since
// the epoch, and a status of 0. When they cannot be read, a handle that is
// not open among them (fstat refuses its missing descriptor), the status is
// -1 and every time -1, and the saved errno says why.
extern "C" void idris_rt_io_file_time(int64_t file, int64_t *status, int64_t *atime_sec,
                                      int64_t *atime_nsec, int64_t *mtime_sec,
                                      int64_t *mtime_nsec, int64_t *ctime_sec,
                                      int64_t *ctime_nsec) {
  int64_t times[6];
  *status = 0;
  if (!rt::platform::fileTimes(rt::io::streamOf(file).descriptor(), times)) {
    rt::io::saveError();
    *status = -1;
    for (int64_t &t : times)
      t = -1;
  }
  *atime_sec = times[0];
  *atime_nsec = times[1];
  *mtime_sec = times[2];
  *mtime_nsec = times[3];
  *ctime_sec = times[4];
  *ctime_nsec = times[5];
}
