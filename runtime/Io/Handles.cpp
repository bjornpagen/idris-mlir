// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The handle table, which stands for every pointer base holds. A handle is
// an int64_t: -1 is null, and any other is the slot of the table it numbers.
// The table is made with four slots: the standard streams, 0, 1 and 2, which
// it never frees, and the runtime's string slot for the environment, 3. A
// slot the program opens holds a file, a directory, a file's times or a
// string. No address reaches the program, and a freed slot is the next one
// taken, so a program that opens and closes files without end keeps a table
// of the size it had open at once.
//
// A string slot is the program's or the runtime's. One read from a file or
// naming the current directory is the program's: base frees it
// (idris_rt_io_handle_free) once it has read it. One from the environment or
// a directory's entries is the runtime's, as getenv's and readdir's bytes are
// the C library's: the runtime keeps one slot for the environment, made with
// the table, and one per open directory, made with it, which the next call
// of its kind refills, and freeing such a handle does nothing.
// releaseHandles releases them all when the program ends.
//
// An operation given a handle that is not open as what it takes (a closed
// file, a directory where a file goes) fails as the C library fails a stream
// that is not open, with EBADF: streamOf decides it once for every operation
// on a stream, openSlot for the others. Reading a handle as a string is
// asked only of one that holds a string: the guard at its call site asks
// first, and crashes there, at the program's place, when it holds none.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "End/End.h"
#include "Io/Io.h"
#include "Platform/Platform.h"
#include "Rc/Rc.h"
#include "Strings/Strings.h"
#include "idris_rt.h"

#include <errno.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace {

using rt::io::ByteRead;
using rt::io::Kind;
using rt::io::Slot;
using rt::io::Stream;
using rt::io::StreamOps;
using rt::io::Written;

// The slots the table is made with, in the order of their handles.
struct Seed {
  Slot slots[4];
};
constexpr Seed seed{{
    {Kind::Input, {}},
    {Kind::Output, {}},
    {Kind::Error, {}},
    {Kind::KeptString, {.string = &rt::strings::emptyString}},
}};
constexpr size_t seedSlots = sizeof seed.slots / sizeof seed.slots[0];
static_assert(seed.slots[rt::io::environmentHandle].kind == Kind::KeptString,
              "the environment's handle is its slot in the seed");

// The table: the seed's storage, which is static and constant-initialized
// (the runtime has no static constructor), until the table outgrows it;
// then raw memory that doubles when every slot is used.
constinit Seed seeded = seed;
Slot *slots = seeded.slots;
size_t slotsUsed = seedSlots;
size_t slotsHeld = seedSlots;
int64_t freeHandle = rt::io::nullHandle;

// What slotOf gives for a handle past the table, null among them: a free
// slot, which every lookup reads as no slot open as what it takes, and
// which nothing writes.
constinit Slot none{Kind::Free, {}};

void grow() {
  size_t held = slotsHeld * 2;
  auto *grown = static_cast<Slot *>(rt::alloc::allocate(held * sizeof(Slot)));
  memcpy(grown, slots, slotsUsed * sizeof(Slot));
  // The seed's storage is the table's own, never allocated.
  if (slots != seeded.slots)
    rt::alloc::release(slots);
  slots = grown;
  slotsHeld = held;
}

// What the slot holds, released: a file closed, which writes what it has
// pending, and how that went; a directory closed; a string losing the
// slot's reference. A directory's entry slot is a slot of its own, and a
// standard stream's state is its row's, not the slot's.
rt::platform::Wrote releasePayload(Slot &slot) {
  switch (slot.kind) {
  case Kind::File:
    return rt::platform::closeFile(slot.file);
  case Kind::Directory:
    if (!rt::platform::closeDirectory(slot.directory.stream))
      rt::io::saveError();
    return rt::platform::Wrote::Whole;
  case Kind::String:
  case Kind::KeptString:
    rt::rc::decCell(slot.string);
    return rt::platform::Wrote::Whole;
  case Kind::Input:
  case Kind::Output:
  case Kind::Error:
  case Kind::Free:
    return rt::platform::Wrote::Whole;
  }
}

// Releases what the slot holds and frees it for the next newSlot.
rt::platform::Wrote freeSlot(int64_t handle) {
  Slot &slot = slots[handle];
  rt::platform::Wrote released = releasePayload(slot);
  slot.kind = Kind::Free;
  slot.nextFree = freeHandle;
  freeHandle = handle;
  return released;
}

// A stream that is not open. streamOf saves EBADF when it finds one, and
// each operation then fails as the C library fails such a stream: nothing
// written or read, a failure, no end, no descriptor.
constexpr StreamOps notOpen{
    .write = [](const Stream &, const char *, size_t) { return Written{0, true}; },
    .read = [](const Stream &, char *, size_t) -> size_t { return 0; },
    .readByte = [](const Stream &) { return ByteRead{ByteRead::Got::Failure, 0}; },
    .flush = [](const Stream &) { return false; },
    .close = [](const Stream &) {},
    .failed = [](const Stream &) { return true; },
    .ended = [](const Stream &) { return false; },
    .descriptor = [](const Stream &) { return -1; },
    .poll = [](const Stream &) -> int64_t { return -1; },
};

// The row of a slot that is a stream, or null for one that is not.
constexpr const StreamOps *rowOf(Kind kind) {
  switch (kind) {
  case Kind::Input:
    return &rt::io::inputStream;
  case Kind::Output:
    return &rt::io::outputStream;
  case Kind::Error:
    return &rt::io::errorStream;
  case Kind::File:
    return &rt::io::fileStream;
  case Kind::Free:
  case Kind::Directory:
  case Kind::String:
  case Kind::KeptString:
    return nullptr;
  }
}

} // namespace

namespace rt::io {

Slot &slotOf(int64_t handle) {
  return static_cast<uint64_t>(handle) < slotsUsed ? slots[handle] : none;
}

Slot *openSlot(int64_t handle, Kind kind) {
  Slot &slot = slotOf(handle);
  if (slot.kind == kind)
    return &slot;
  fail(EBADF);
  return nullptr;
}

Stream streamOf(int64_t handle) {
  Slot &slot = slotOf(handle);
  if (const StreamOps *row = rowOf(slot.kind))
    return {row, handle, &slot};
  fail(EBADF);
  return {&notOpen, handle, &slot};
}

int64_t newSlot(Kind kind) {
  int64_t handle = freeHandle;
  if (handle != nullHandle) {
    freeHandle = slots[handle].nextFree;
  } else {
    if (slotsUsed == slotsHeld)
      grow();
    handle = static_cast<int64_t>(slotsUsed++);
  }
  slots[handle].kind = kind;
  return handle;
}

int64_t newString(const idris_rt_str *s) {
  int64_t handle = newSlot(Kind::String);
  slots[handle].string = s;
  return handle;
}

void keepString(int64_t handle, const idris_rt_str *s) {
  Slot &slot = slots[handle];
  rt::rc::decCell(slot.string);
  slot.string = s;
}

// A directory owns the slot of its entry, made with it, which goes after
// it: the slot is read before freeing writes over it.
rt::platform::Wrote releaseSlot(int64_t handle) {
  Slot released = slots[handle];
  rt::platform::Wrote how = freeSlot(handle);
  if (released.kind == Kind::Directory)
    (void)freeSlot(released.directory.entry);
  return how;
}

void releaseHandles() {
  for (size_t i = 0; i < slotsUsed; ++i)
    (void)releasePayload(slots[i]);
  if (slots != seeded.slots)
    rt::alloc::release(slots);
  seeded = seed;
  slots = seeded.slots;
  slotsUsed = slotsHeld = seedSlots;
  freeHandle = nullHandle;
}

} // namespace rt::io

// Whether a handle holds a string, the program's or the runtime's: what the
// guard before base's getString asks, crashing at the program's place when
// it does not.
extern "C" bool idris_rt_handle_holds_string(int64_t handle) {
  rt::io::Kind kind = rt::io::slotOf(handle).kind;
  return kind == rt::io::Kind::String || kind == rt::io::Kind::KeptString;
}

// Base's getString: the string a string handle holds, with one more
// reference, of a handle its guard found to hold one.
extern "C" const idris_rt_str *idris_rt_handle_string(int64_t handle) {
  const rt::io::Slot &slot = rt::io::slotOf(handle);
  rt::rc::incCell(slot.string);
  return slot.string;
}

// Base's free of a pointer: releases the slot and what it holds, when it is
// the program's. The runtime's own, the standard streams and the strings it
// keeps, and a handle with no open slot, null among them, are left alone.
extern "C" void idris_rt_io_handle_free(int64_t handle) {
  switch (rt::io::slotOf(handle).kind) {
  case rt::io::Kind::File:
  case rt::io::Kind::Directory:
  case rt::io::Kind::String:
    switch (rt::io::releaseSlot(handle)) {
    case rt::platform::Wrote::Whole:
      return;
    case rt::platform::Wrote::Broken:
      rt::end::end(rt::end::Piped{});
    case rt::platform::Wrote::Failed:
      rt::io::saveError();
      return;
    }
    return;
  case rt::io::Kind::Input:
  case rt::io::Kind::Output:
  case rt::io::Kind::Error:
  case rt::io::Kind::KeptString:
  case rt::io::Kind::Free:
    return;
  }
}
