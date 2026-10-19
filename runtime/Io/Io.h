// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
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

// The size of the buffers of standard output and input: a buffer, not a
// page. It bounds one write's worth of pending output and is never an
// alignment or a region size (the target entry's page size is
// IDRIS_MLIR_PAGE_SIZE, which rt::platform's startup check reads); 4096 is a
// small write's worth on every target. A test build may set
// IDRIS_RT_IO_BUFFER_SIZE to a few bytes, so that every boundary of the
// buffers is reached with little data (tests/io-buffer); the
// production build sets nothing.
#ifndef IDRIS_RT_IO_BUFFER_SIZE
#define IDRIS_RT_IO_BUFFER_SIZE 4096
#endif
inline constexpr size_t bufferSize = IDRIS_RT_IO_BUFFER_SIZE;
static_assert(bufferSize >= 4, "the output buffer holds a character's longest UTF-8, which "
                               "idris_rt_io_put_char encodes in place");

// Errors (Errors.cpp): the errno base reads after a call that failed.

// The errno of the last failing call. A call that succeeds leaves it.
extern int64_t savedErrno;

// The call that just failed left its errno with the C library.
void saveError();

// The call failed for a reason of the runtime's, named as C names it.
void fail(int code);

// The handle table (Handles.cpp).

inline constexpr int64_t nullHandle = -1;

// What a slot holds: a standard stream, which the table is made with and
// never frees; an open file, an open directory or a file's times; or a
// string, the program's, which freeing its handle releases, or the runtime's
// (Kept), which only the next call of its kind or the end of the program
// releases.
enum class Kind : uint8_t {
  Free,
  Input,
  Output,
  Error,
  File,
  Directory,
  Times,
  String,
  KeptString
};

// An open directory, and the handle of the string slot that holds its last
// entry's name: made with it, holding the empty string until it has one.
struct DirectoryPayload {
  rt::platform::Directory *stream;
  int64_t entry;
};

struct Slot {
  Kind kind;
  union {
    rt::platform::File *file;
    DirectoryPayload directory;
    // Seconds and nanoseconds of a file's access, modification and status
    // change times; -1 each when they could not be read.
    int64_t times[6];
    // A string of either kind: one reference, the slot's.
    const idris_rt_str *string;
    // The next free slot's handle, or null.
    int64_t nextFree;
  };
};

// The runtime's string slot for the environment, which the table is made
// with after the standard streams.
inline constexpr int64_t environmentHandle = 3;

// The slot of a handle. A handle past the table, null among them, has a
// free one, which nothing writes. Valid until the next newSlot, which may
// move the table.
Slot &slotOf(int64_t handle);

// The slot of a handle open as `kind`, or null after saving EBADF.
Slot *openSlot(int64_t handle, Kind kind);

// A new slot of `kind`, the program's, whose payload the caller writes.
int64_t newSlot(Kind kind);

// A new string slot holding s, whose reference it takes: the program's.
int64_t newString(const idris_rt_str *s);

// The runtime's string slot `handle` holding s instead of what it held.
void keepString(int64_t handle, const idris_rt_str *s);

// Releases what the slot holds, and with a directory the slot of its entry,
// and frees the slot for the next newSlot.
void releaseSlot(int64_t handle);

// Releases what every slot holds: open files are closed, which writes what
// they have pending, and the strings the runtime keeps lose their reference.
// The table is then as it was made. When the program ends, so that what it
// leaves in the table is no live cell.
void releaseHandles();

// Streams: what a handle that names one reads and writes, through the row
// of its kind.

// What a write did: the bytes it wrote, and whether it failed before it
// wrote them all (errno saved). A write to a stream that is not open for
// writing fails having written none, even of none.
struct Written {
  size_t count;
  bool failed;
};

// What reading a byte gave: a byte, the end of the stream's input, or a
// failure (errno saved), which C's getc tells apart only by ferror.
struct ByteRead {
  enum class Got : uint8_t { Byte, End, Failure };
  Got got;
  unsigned char byte;
};

struct Stream;

// A kind of stream's operations, one row of them per kind: every entry point
// that takes a stream calls its row, so what a stream does is decided where
// the stream is, once. An operation the stream cannot do fails as the C
// library fails it on a stream not open for it, with EBADF.
struct StreamOps {
  // The n bytes at p, in order with every other write to the stream.
  Written (*write)(const Stream &stream, const char *p, size_t n);
  // Up to n bytes into p, waiting until n bytes or the end: fewer only at the
  // end or on a failure (errno saved).
  size_t (*read)(const Stream &stream, char *p, size_t n);
  // The next byte, consumed.
  ByteRead (*readByte)(const Stream &stream);
  // Writes what the stream has pending; false when that failed (errno
  // saved).
  bool (*flush)(const Stream &stream);
  // Closes the stream: a file's handle is freed, and a standard stream stays
  // open, since the runtime writes and reads it.
  void (*close)(const Stream &stream);
  // C's ferror: a read or a write on the stream failed.
  bool (*failed)(const Stream &stream);
  // C's feof: a read met the end of the stream's input.
  bool (*ended)(const Stream &stream);
  // The stream's descriptor, or -1 when it has none.
  int (*descriptor)(const Stream &stream);
  // Whether the stream has input ready, waiting up to a second for it, as
  // select says: 1 when it has, 0 when it has not, -1 on a failure.
  int64_t (*poll)(const Stream &stream);
};

// The rows of the standard streams (Input.cpp, Output.cpp) and of a file
// (Files.cpp).
extern const StreamOps inputStream;
extern const StreamOps outputStream;
extern const StreamOps errorStream;
extern const StreamOps fileStream;

// A handle as a stream: its row, its handle and its slot, whose file the
// file row reads.
struct Stream {
  const StreamOps *ops;
  int64_t handle;
  Slot *slot;

  Written write(const char *p, size_t n) const { return ops->write(*this, p, n); }
  size_t read(char *p, size_t n) const { return ops->read(*this, p, n); }
  ByteRead readByte() const { return ops->readByte(*this); }
  bool flush() const { return ops->flush(*this); }
  void close() const { ops->close(*this); }
  bool failed() const { return ops->failed(*this); }
  bool ended() const { return ops->ended(*this); }
  int descriptor() const { return ops->descriptor(*this); }
  int64_t poll() const { return ops->poll(*this); }
};

// The stream a handle names: a standard stream or an open file. Any other
// handle, null, closed, or of a directory, a file time or a string, is a
// stream that is not open: EBADF is saved here, and its every operation
// then fails as the C library fails a stream that is not open, without
// another test.
Stream streamOf(int64_t handle);

// Whether a stream has input ready, as its descriptor says (StreamOps::poll).
int64_t pollDescriptor(const Stream &stream);

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

// Bytes on a handle (Bytes.cpp), as the ABI gives them: the count written
// or read, fewer on a failure (errno saved), and 0 when the handle is no
// stream to write to or read from (EBADF).
size_t writeBytes(int64_t handle, const char *p, size_t n);
size_t readBytes(int64_t handle, char *p, size_t n);

} // namespace rt::io
