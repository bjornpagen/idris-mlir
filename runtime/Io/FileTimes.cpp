// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A file's times (System.File.Meta's fileTime): read at once, as the one
// call of the system gives them, into a slot of the handle table, which
// base reads one field at a time and frees. Each field's reader is one
// instance of a function over the field, so no field is passed or tested
// at run time.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stdint.h>

namespace {

using idr::files::FileTimeField;

// The field of the times a handle holds, or -1 for a handle that holds
// none, which base, whose only file-time handles are its own fileTime's,
// never reads.
template <FileTimeField F>
int64_t field(int64_t handle) {
  const rt::io::Slot &slot = rt::io::slotOf(handle);
  return slot.kind == rt::io::Kind::FileTimes ? (*slot.times)[F] : -1;
}

} // namespace

// The access, modification and status change times of the file the handle's
// stream names, as fstat gives them, in a new file-time slot, the
// program's. When they cannot be read, a handle that is not open among them
// (fstat refuses its missing descriptor), every field is -1 and the saved
// errno says why.
extern "C" int64_t idris_rt_io_file_time(int64_t file) {
  auto *times = static_cast<rt::platform::FileTimes *>(
      rt::alloc::allocate(sizeof(rt::platform::FileTimes)));
  if (!rt::platform::fileTimes(rt::io::descriptorOf(file), *times)) {
    rt::io::saveError();
    times->items.fill(-1);
  }
  int64_t handle = rt::io::newSlot(rt::io::Kind::FileTimes);
  rt::io::slotOf(handle).times = times;
  return handle;
}

// Each field, in seconds or nanoseconds since the epoch: of the last access,
// the last modification and the last status change.
extern "C" int64_t idris_rt_handle_file_time_atime_sec(int64_t handle) {
  return field<FileTimeField::AccessSeconds>(handle);
}
extern "C" int64_t idris_rt_handle_file_time_atime_nsec(int64_t handle) {
  return field<FileTimeField::AccessNanoseconds>(handle);
}
extern "C" int64_t idris_rt_handle_file_time_mtime_sec(int64_t handle) {
  return field<FileTimeField::ModifiedSeconds>(handle);
}
extern "C" int64_t idris_rt_handle_file_time_mtime_nsec(int64_t handle) {
  return field<FileTimeField::ModifiedNanoseconds>(handle);
}
extern "C" int64_t idris_rt_handle_file_time_ctime_sec(int64_t handle) {
  return field<FileTimeField::StatusSeconds>(handle);
}
extern "C" int64_t idris_rt_handle_file_time_ctime_nsec(int64_t handle) {
  return field<FileTimeField::StatusNanoseconds>(handle);
}
