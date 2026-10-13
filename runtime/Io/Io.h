// rt::io: the program's input and output, and its end: standard output and
// input through static buffers; base's files, directories, process,
// terminal, errors and clocks over the platform layer (rt::platform), whose
// pointers are handles of one table; and crash.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace rt::io {

// Writing (Writing.cpp).

// The size of the buffers of standard output and input: a buffer, not a
// page. It bounds one write's worth of pending output and is never an
// alignment or a region size (the target entry's page size is
// IDRIS_MLIR_PAGE_SIZE, which rt::platform's startup check reads); 4096 is a
// small write's worth on every target.
inline constexpr size_t bufferSize = 4096;

// Stores, which stay stores. A memcpy a compiler invents for the same copy
// can be dropped or moved past the length that publishes the bytes.
inline void copyOut(volatile char *to, const char *from, size_t n) {
  for (size_t i = 0; i < n; ++i)
    to[i] = from[i];
}

// Writes n bytes to fd, looping over partial writes; a failed write abandons
// the rest.
void writeAll(int fd, const char *p, size_t n);

// Errors (Errors.cpp): the errno base reads after a call that failed.

// The errno of the last failing call. A call that succeeds leaves it.
extern int64_t savedErrno;

// The call that just failed left its errno with the C library.
void saveError();

// The call failed for a reason of the runtime's, named as C names it.
void fail(int code);

// The handle table (Handles.cpp).

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
extern int64_t environmentHandle;

// The slot of a handle the table holds, of any kind but free, or null.
// Valid until the next newSlot, which may move the table.
Slot *slotOf(int64_t handle);

// The slot of a handle open as `kind`, or null after saving EBADF.
Slot *openSlot(int64_t handle, Kind kind);

// The stream of an open file, or null after saving EBADF: the standard
// streams have none, and their callers take them first.
rt::platform::File *fileOf(int64_t handle);

// A new slot of `kind`, the program's, whose payload the caller writes.
int64_t newSlot(Kind kind);

// A new string slot holding s, whose reference it takes: the program's.
int64_t newString(const idris_rt_str *s);

// The runtime's string slot `handle` holding s instead of what it held, or a
// new one when `handle` is null; its handle.
int64_t keepString(int64_t handle, const idris_rt_str *s);

// Releases what the slot holds, and with a directory the slot of its entry,
// and frees the slot for the next newSlot.
void releaseSlot(int64_t handle);

// Releases every slot and what it holds: open files are closed, which writes
// what they have pending, and the strings the runtime keeps lose their
// reference. When the program ends, so that what it leaves in the table is
// no live cell.
void releaseHandles();

// Scratch (Scratch.cpp): bytes being gathered before they become a string
// or go to the C library: a line being read, a path.

// A growable run of bytes: on the stack up to a buffer's worth, then raw
// memory.
struct Scratch {
  char inline_[bufferSize];
  char *bytes = inline_;
  size_t length = 0;
  size_t capacity = bufferSize;
  Scratch() = default;
  Scratch(const Scratch &) = delete;
  Scratch &operator=(const Scratch &) = delete;
  ~Scratch();
  // Room for n more bytes, from bytes + length.
  void reserve(size_t n);
  void push(char c) {
    reserve(1);
    bytes[length++] = c;
  }
  void append(const char *p, size_t n);
};

// A string as the C library takes one: its bytes, gathered in `scratch`, and
// a NUL after them. A NUL in the string ends it there.
const char *cText(Scratch &scratch, const idris_rt_str *s);

// Standard input (Input.cpp), through a buffer that a read fills.

extern char input[bufferSize];
extern size_t inputPosition;
extern size_t inputLength;
// Set once a read failed: what C's ferror reports, which base asks after a
// read that gave nothing.
extern bool inputFailed;

// The next input byte, or -1 at the end of input or when the read failed.
// Pending output is written before the program blocks reading.
int32_t peek();

// Up to `count` input bytes into `to`, waiting for each until the end of
// input: fewer only there. Gives the count read.
size_t readInput(char *to, size_t count);

// Standard output (Output.cpp), through a buffer that a flush writes.
void putBytes(const char *p, size_t n);

// Bytes on a handle (Bytes.cpp).

// The n bytes at p to a handle, in order with every other write to it:
// standard output through its buffer, standard error after what standard
// output has pending, a file through its stream. Gives the count written,
// fewer when the write failed (errno saved), or -1 when the handle is no
// stream to write to (EBADF).
int64_t writeBytes(int64_t handle, const char *p, size_t n);

// Up to n bytes from a handle into p: standard input through its buffer, a
// file through its stream, waiting until n bytes or the end. Gives the count
// read, fewer at the end or when the read failed (errno saved), or -1 when the
// handle is no stream to read from (EBADF).
int64_t readBytes(int64_t handle, char *p, size_t n);

// Files (Files.cpp).

// The descriptor of a standard stream or an open file, or -1 when the handle
// is neither (EBADF).
int descriptorOf(int64_t handle);

} // namespace rt::io
