// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::io: the program's input and output: standard output and input through
// static buffers; base's files, directories, process, terminal, errors and
// clocks over the platform layer (rt::platform), whose pointers are handles
// of one table. A write a reader gone refuses ends the program (rt::end).
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "Platform/Platform.h"
#include "idr/IR/Generated/Handles.h.inc"
#include "idris_rt.h"

#include <errno.h>
#include <stddef.h>
#include <stdint.h>

#include <concepts>

namespace rt::io {

// The size of the buffers of standard output and input: one page of the
// target's, the unit the kernel moves a pipe's or a file's bytes in, so a
// full buffer is one write the kernel takes whole. It bounds one write's
// worth of pending output; a test reaches every boundary of the buffers by
// writing past one.
inline constexpr size_t bufferSize = rt::platform::pageSize();
static_assert(bufferSize >= 4, "the output buffer holds a character's longest UTF-8, which "
                               "idris_rt_io_put_char encodes in place");

// Errors (Errors.cpp): the errno base reads after a call that failed.

// The errno of the last failing call. A call that succeeds leaves it.
extern int64_t savedErrno;

// The call that just failed left its errno with the C library.
void saveError();

// The call failed for a reason of the runtime's, named as C names it.
void fail(int code);

// The handle table (Handles.cpp). Its null handle and the standard
// streams' handles are the specification's (idr::handles), which a
// program's constants are written from too, so neither side restates them.

// What a slot holds: a standard stream, which the table is made with and
// never frees; an open file or an open directory; a file's times, read at
// once; or a string, the program's, which freeing its handle releases, or
// the runtime's (Kept), which only the next call of its kind or the end of
// the program releases.
enum class Kind : uint8_t {
  Free,
  Input,
  Output,
  Error,
  File,
  Directory,
  FileTimes,
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
    // A file's times, in memory of their own, which the slot owns.
    rt::platform::FileTimes *times;
    // A string of either kind: one reference, the slot's.
    const idris_rt_str *string;
    // The next free slot's handle, or null.
    int64_t nextFree;
  };
};

// The runtime's string slot for the environment, which the table is made
// with after the standard streams.
inline constexpr int64_t environmentHandle =
    static_cast<int64_t>(idr::EnumTraits<idr::handles::StandardStream>::count);

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
// and frees the slot for the next newSlot; how closing a file, which writes
// what it has pending, went.
rt::platform::Wrote releaseSlot(int64_t handle);

// Releases what every slot holds: open files are closed, which writes what
// they have pending, and the strings the runtime keeps lose their reference.
// The table is then as it was made. When the program ends, however it ends
// but by an internal error, so that what it wrote to a file before its end
// is in the file; a failure here changes nothing of how it ends.
void releaseHandles();

// Writes standard output's pending bytes (Output.cpp), and how that went:
// what every ending writes first.
rt::platform::Wrote writePending();

// Standard output's writes (Output.cpp): the n bytes at p after what is
// pending, through the buffer, or at once when they are more than it holds;
// and, for text formatted where it goes, room for n bytes, at most the
// buffer's, after a flush when they would not fit, whose first n bytes
// outputWritten then makes pending.
void putOutput(const char *p, size_t n);
char *outputRoom(size_t n);
void outputWritten(size_t n);

// Streams: what a handle that names one reads and writes. The kinds of
// stream are a closed set, each a type of its own with the operations every
// stream has (Stream): standard input, output and error, an open file, and
// the stream of a handle that names none open. Which one a handle names is
// read once, from its slot, by withStream, which hands it to the caller's
// code, compiled for each kind. An operation the stream cannot do fails as
// the C library fails it on a stream not open for it, with EBADF.

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

// What every kind of stream does:
// - write: the n bytes at p, in order with every other write to the stream;
// - read: up to n bytes into p, waiting until n bytes or the end: fewer only
//   at the end or on a failure (errno saved);
// - readByte: the next byte, consumed;
// - flush: writes what the stream has pending; false when that failed
//   (errno saved);
// - close: a file's handle is freed, and a standard stream stays open,
//   since the runtime writes and reads it;
// - failed: C's ferror, a read or a write on the stream failed;
// - ended: C's feof, a read met the end of the stream's input;
// - descriptor: the stream's descriptor, or -1 when it has none;
// - poll: whether the stream has input ready, waiting up to a second for
//   it, as select says: 1 when it has, 0 when it has not, -1 on a failure.
template <class S>
concept Stream = requires(const S &stream, const char *from, char *into, size_t n) {
  { stream.write(from, n) } -> std::same_as<Written>;
  { stream.read(into, n) } -> std::same_as<size_t>;
  { stream.readByte() } -> std::same_as<ByteRead>;
  { stream.flush() } -> std::same_as<bool>;
  { stream.close() } -> std::same_as<void>;
  { stream.failed() } -> std::same_as<bool>;
  { stream.ended() } -> std::same_as<bool>;
  { stream.descriptor() } -> std::same_as<int>;
  { stream.poll() } -> std::same_as<int64_t>;
};

// Standard input, the handle 0 (Input.cpp).
struct InputStream {
  Written write(const char *p, size_t n) const;
  size_t read(char *p, size_t n) const;
  ByteRead readByte() const;
  bool flush() const;
  void close() const;
  bool failed() const;
  bool ended() const;
  int descriptor() const;
  int64_t poll() const;
};

// Standard output, the handle 1 (Output.cpp).
struct OutputStream {
  Written write(const char *p, size_t n) const;
  size_t read(char *p, size_t n) const;
  ByteRead readByte() const;
  bool flush() const;
  void close() const;
  bool failed() const;
  bool ended() const;
  int descriptor() const;
  int64_t poll() const;
};

// Standard error, the handle 2 (Output.cpp).
struct ErrorStream {
  Written write(const char *p, size_t n) const;
  size_t read(char *p, size_t n) const;
  ByteRead readByte() const;
  bool flush() const;
  void close() const;
  bool failed() const;
  bool ended() const;
  int descriptor() const;
  int64_t poll() const;
};

// An open file: its handle, which closing it frees, and the C library's
// stream its slot holds (Files.cpp).
struct FileStream {
  int64_t handle;
  rt::platform::File *file;

  Written write(const char *p, size_t n) const;
  size_t read(char *p, size_t n) const;
  ByteRead readByte() const;
  bool flush() const;
  void close() const;
  bool failed() const;
  bool ended() const;
  int descriptor() const;
  int64_t poll() const;
};

// The stream of a handle that names none open. withStream saved EBADF when
// it found one, and each operation then fails as the C library fails such a
// stream: nothing written or read, a failure, no end, no descriptor.
struct NotOpenStream {
  Written write(const char *, size_t) const { return {0, true}; }
  size_t read(char *, size_t) const { return 0; }
  ByteRead readByte() const { return {ByteRead::Got::Failure, 0}; }
  bool flush() const { return false; }
  void close() const {}
  bool failed() const { return true; }
  bool ended() const { return false; }
  int descriptor() const { return -1; }
  int64_t poll() const { return -1; }
};

// The kinds of stream, each a Stream: what withStream hands its caller's
// code, which is compiled for each.
template <Stream... Kinds>
struct StreamKinds {
  template <class Use>
  static constexpr bool usedBy = (std::invocable<Use &, const Kinds &> && ...);
};
using EveryStream =
    StreamKinds<InputStream, OutputStream, ErrorStream, FileStream, NotOpenStream>;

template <class Use>
concept UsesStream = EveryStream::usedBy<Use>;

// Whether a descriptor has input ready, as select says (Stream's poll).
int64_t pollDescriptor(int descriptor);

// The stream a handle names, given to `use`: a standard stream or an open
// file. Any other handle, null, closed, or of a directory, a file time or a
// string, names the stream that is not open: EBADF is saved here, and its
// every operation then fails as the C library fails a stream that is not
// open, without another test.
template <UsesStream Use>
decltype(auto) withStream(int64_t handle, Use &&use) {
  Slot &slot = slotOf(handle);
  switch (slot.kind) {
  case Kind::Input:
    return use(InputStream{});
  case Kind::Output:
    return use(OutputStream{});
  case Kind::Error:
    return use(ErrorStream{});
  case Kind::File:
    return use(FileStream{handle, slot.file});
  case Kind::Free:
  case Kind::Directory:
  case Kind::FileTimes:
  case Kind::String:
  case Kind::KeptString:
    break;
  }
  fail(EBADF);
  return use(NotOpenStream{});
}

// The descriptor of the stream a handle names, what fstat and isatty take:
// -1, with EBADF saved, for a handle that names none open, which they then
// refuse as such.
inline int descriptorOf(int64_t handle) {
  return withStream(handle, [](const Stream auto &stream) { return stream.descriptor(); });
}

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
