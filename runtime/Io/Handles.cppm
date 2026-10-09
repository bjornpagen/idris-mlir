// rt.io:handles: the handle table, which stands for every pointer base
// holds. A handle is an int64_t: 0, 1 and 2 are the standard streams, -1 is
// null, and handle i + 3 is slot i of the table, which holds an open file, an
// open directory, a file's times or a string. No address reaches the
// program, and a freed slot is the next one taken, so a program that opens
// and closes files without end keeps a table of the size it had open at once.
//
// A string slot is the program's or the runtime's. One read from a file or
// naming the current directory is the program's: base frees it
// (idris_rt_io_handle_free) once it has read it. One from the environment or
// a directory's entries is the runtime's, as getenv's and readdir's bytes are
// the C library's: the runtime keeps one slot for the environment and one per
// open directory, which the next call of its kind refills, and freeing such a
// handle does nothing. releaseHandles releases them all when the program ends.
//
// An operation given a handle that is not open as what it takes (a closed
// file, a directory where a file goes) fails as the C library fails a stream
// that is not open, with EBADF.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

export module rt.io:handles;

import rt.alloc;
import rt.platform;
import :errors;

namespace rt::io {

inline constexpr int64_t nullHandle = -1;
// The handle of slot 0, after the standard streams.
inline constexpr int64_t firstHandle = 3;

enum class Kind : uint8_t { Free, File, Directory, Times, String };

// An open directory, and the handle of the string slot that holds its last
// entry's name, null until it has one.
struct DirectoryPayload {
  rt::platform::Directory *stream;
  int64_t entry;
};

struct Slot {
  Kind kind;
  // A string the runtime keeps, which freeing its handle leaves alone.
  bool kept;
  union {
    rt::platform::File *file;
    DirectoryPayload directory;
    // Seconds and nanoseconds of a file's access, modification and status
    // change times; -1 each when they could not be read.
    int64_t times[6];
    // One reference, the slot's.
    const idris_rt_str *string;
    // The next free slot's handle, or null.
    int64_t nextFree;
  };
};

// The runtime's string slot for the environment, null until a call made it.
inline int64_t environmentHandle = nullHandle;

} // namespace rt::io

namespace {

using rt::io::Slot;

rt::io::Slot *slots = nullptr;
size_t slotsUsed = 0;
size_t slotsHeld = 0;
int64_t freeHandle = rt::io::nullHandle;

// The slots, in raw memory that doubles when they are all used.
void grow() {
  size_t held = slotsHeld == 0 ? 1 : slotsHeld * 2;
  auto *grown = static_cast<Slot *>(rt::alloc::allocate(held * sizeof(Slot)));
  if (slots != nullptr) {
    memcpy(grown, slots, slotsUsed * sizeof(Slot));
    rt::alloc::release(slots);
  }
  slots = grown;
  slotsHeld = held;
}

// What the slot holds, released: a file closed, a directory closed, a string
// losing the slot's reference. A directory's entry slot is a slot of its own.
void releasePayload(Slot &slot) {
  switch (slot.kind) {
  case rt::io::Kind::File:
    if (!rt::platform::closeFile(slot.file))
      rt::io::saveError();
    break;
  case rt::io::Kind::Directory:
    if (!rt::platform::closeDirectory(slot.directory.stream))
      rt::io::saveError();
    break;
  case rt::io::Kind::String:
    idris_rt_dec(const_cast<idris_rt_str *>(slot.string));
    break;
  case rt::io::Kind::Times:
  case rt::io::Kind::Free:
    break;
  }
}

} // namespace

namespace rt::io {

// The slot of a handle the table holds, of any kind but free, or null.
// Valid until the next newSlot, which may move the table.
Slot *slotOf(int64_t handle) {
  if (handle < firstHandle || static_cast<uint64_t>(handle - firstHandle) >= slotsUsed)
    return nullptr;
  Slot &slot = slots[handle - firstHandle];
  return slot.kind == Kind::Free ? nullptr : &slot;
}

// The slot of a handle open as `kind`, or null after saving EBADF.
Slot *openSlot(int64_t handle, Kind kind) {
  Slot *slot = slotOf(handle);
  if (slot != nullptr && slot->kind == kind)
    return slot;
  fail(EBADF);
  return nullptr;
}

// The stream of an open file, or null after saving EBADF: the standard
// streams have none, and their callers take them first.
rt::platform::File *fileOf(int64_t handle) {
  Slot *slot = openSlot(handle, Kind::File);
  return slot == nullptr ? nullptr : slot->file;
}

// A new slot of `kind`, the program's, whose payload the caller writes.
int64_t newSlot(Kind kind) {
  int64_t handle = freeHandle;
  if (handle != nullHandle) {
    freeHandle = slots[handle - firstHandle].nextFree;
  } else {
    if (slotsUsed == slotsHeld)
      grow();
    handle = static_cast<int64_t>(slotsUsed++) + firstHandle;
  }
  Slot &slot = slots[handle - firstHandle];
  slot.kind = kind;
  slot.kept = false;
  return handle;
}

// A new string slot holding s, whose reference it takes: the program's.
int64_t newString(const idris_rt_str *s) {
  int64_t handle = newSlot(Kind::String);
  slots[handle - firstHandle].string = s;
  return handle;
}

// The runtime's string slot `handle` holding s instead of what it held, or a
// new one when `handle` is null; its handle.
int64_t keepString(int64_t handle, const idris_rt_str *s) {
  if (handle == nullHandle) {
    handle = newString(s);
    slots[handle - firstHandle].kept = true;
    return handle;
  }
  Slot &slot = slots[handle - firstHandle];
  idris_rt_dec(const_cast<idris_rt_str *>(slot.string));
  slot.string = s;
  return handle;
}

// Releases what the slot holds, and with a directory the slot of its entry,
// and frees the slot for the next newSlot.
void releaseSlot(int64_t handle) {
  Slot &slot = slots[handle - firstHandle];
  int64_t entry = slot.kind == Kind::Directory ? slot.directory.entry : nullHandle;
  releasePayload(slot);
  slot.kind = Kind::Free;
  slot.nextFree = freeHandle;
  freeHandle = handle;
  if (entry != nullHandle)
    releaseSlot(entry);
}

} // namespace rt::io

export namespace rt::io {

// Releases every slot and what it holds: open files are closed, which writes
// what they have pending, and the strings the runtime keeps lose their
// reference. When the program ends, so that what it leaves in the table is
// no live cell.
void releaseHandles() {
  for (size_t i = 0; i < slotsUsed; ++i)
    releasePayload(slots[i]);
  if (slots != nullptr)
    rt::alloc::release(slots);
  slots = nullptr;
  slotsUsed = slotsHeld = 0;
  freeHandle = nullHandle;
  environmentHandle = nullHandle;
}

} // namespace rt::io

// Base's null pointer: the handle -1.
extern "C" int64_t idris_rt_handle_is_null(int64_t handle) {
  return handle == rt::io::nullHandle ? 1 : 0;
}

// Base's getString. A handle that holds no string is a pointer no primitive
// gave as a string, and reading one is a crash.
extern "C" const idris_rt_str *idris_rt_handle_string(int64_t handle) {
  rt::io::Slot *slot = rt::io::slotOf(handle);
  if (slot == nullptr || slot->kind != rt::io::Kind::String) {
    static constexpr char message[] = "idris-mlir: a pointer read as a string holds none\n";
    idris_rt_crash(message, sizeof message - 1);
  }
  idris_rt_inc(const_cast<idris_rt_str *>(slot->string));
  return slot->string;
}

// Base's free of a pointer: releases the slot and what it holds. The
// standard streams, null, a handle not open, and a string the runtime keeps
// are left alone.
extern "C" void idris_rt_io_handle_free(int64_t handle) {
  rt::io::Slot *slot = rt::io::slotOf(handle);
  if (slot == nullptr || slot->kept)
    return;
  rt::io::releaseSlot(handle);
}
