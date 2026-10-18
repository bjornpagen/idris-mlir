// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A file's times (System.File.Meta's fileTime): read at once into a file-time
// handle, which base reads field by field and then frees.
// PIN(runtime-quarantine) — see PINS.md
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace {

// The fields of a file time, in the order the slot holds them.
enum Field : size_t { AccessSec, AccessNsec, ModifiedSec, ModifiedNsec, StatusSec, StatusNsec };

// A field of a file-time handle, or -1 when the handle is not one (EBADF).
int64_t field(int64_t time, Field which) {
  rt::io::Slot *slot = rt::io::openSlot(time, rt::io::Kind::Times);
  return slot == nullptr ? -1 : slot->times[which];
}

} // namespace

// The access, modification and status change times of the file the handle's
// stream names, as fstat gives them, each in seconds and nanoseconds since
// the epoch: a new file-time handle, which the program frees. When they
// cannot be read, a handle that is not open among them (fstat refuses its
// missing descriptor), every field is -1, and base, which takes an access
// time of 0 or less for a failure, reads the saved errno.
extern "C" int64_t idris_rt_io_file_time(int64_t file) {
  int64_t times[6];
  if (!rt::platform::fileTimes(rt::io::streamOf(file).descriptor(), times)) {
    rt::io::saveError();
    for (int64_t &t : times)
      t = -1;
  }
  int64_t handle = rt::io::newSlot(rt::io::Kind::Times);
  rt::io::Slot &slot = rt::io::slotOf(handle);
  for (size_t i = 0; i < 6; ++i)
    slot.times[i] = times[i];
  return handle;
}

// The seconds and nanoseconds of a file time's access, modification and
// status change times.
extern "C" int64_t idris_rt_io_file_atime_sec(int64_t time) { return field(time, AccessSec); }
extern "C" int64_t idris_rt_io_file_atime_nsec(int64_t time) { return field(time, AccessNsec); }
extern "C" int64_t idris_rt_io_file_mtime_sec(int64_t time) { return field(time, ModifiedSec); }
extern "C" int64_t idris_rt_io_file_mtime_nsec(int64_t time) { return field(time, ModifiedNsec); }
extern "C" int64_t idris_rt_io_file_ctime_sec(int64_t time) { return field(time, StatusSec); }
extern "C" int64_t idris_rt_io_file_ctime_nsec(int64_t time) { return field(time, StatusNsec); }
