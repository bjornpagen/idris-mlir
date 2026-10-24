// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::platform: what the runtime asks of the operating system and the
// processor, behind one interface whose implementations a target entry
// (CMakeLists.txt) picks: Platform/Posix's serve every POSIX system; the
// operating system's own unit (Platform/Linux, Platform/Darwin) reads what
// the host decides and only it knows how to (where its address space is
// free, its limits, what its signal delivery takes, what its stat calls its
// times); and the startup of the processor's features has its own file, one
// per processor (Platform/X86_64/Cpu.cpp), or one per operating system
// where compiler-rt starts them by an entry of each one's own
// (Platform/Aarch64/Darwin.cpp, Platform/Aarch64/Linux.cpp). The host's
// facts are read once, at start, and kept by whoever asked.
//
// What runs before the processor test (the page-size check, the test, and
// what they write and how they end the process) is marked
// IDRIS_RT_BASELINE (idris_rt.h): idris-mlir keeps such a function compiled
// for the target's baseline, where every other takes the program's CPU.
#pragma once

#include "idris_rt.h"

// The ending table: the signals an ending raises. The clock kinds a
// program reads, and the fields of a file's times.
#include "idr/IR/Generated/Clocks.h.inc"
#include "idr/IR/Generated/Endings.h.inc"
#include "idr/IR/Generated/FileTimes.h.inc"

#include <dirent.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/stat.h>
#include <time.h>

namespace rt::platform {

// Clocks (Posix/Clocks.cpp).

// The clock's reading; false when the system cannot read it.
bool readClock(idr::clocks::ClockKind clock, int64_t &seconds, int64_t &nanoseconds) noexcept;

// The processor (the target entry's unit, IDRIS_MLIR_RUNTIME_CPU_TEST).

// The IDRIS_RT_CPU_FEATURES bits of the features this processor has and
// the operating system supports. It is compiled for the target's baseline
// and kept there (IDRIS_RT_BASELINE, at its definition), since it runs
// before anything shows that the processor has more.
uint64_t cpuFeatures() noexcept;

// Directories (Posix/Directories.cpp).

// An open directory: the C library's stream of its entries.
using Directory = DIR;

Directory *openDirectory(const char *path) noexcept;
bool closeDirectory(Directory *directory) noexcept;

// The name of the directory's next entry, valid until the next call on it,
// or null at its end or on a failure. lastError is then 0 at the end and the
// failure's otherwise.
const char *nextEntry(Directory *directory) noexcept;

// The current directory's path, with a NUL after it, in the `size` bytes at
// `buffer`; false when it cannot be read, or does not fit (lastError is then
// ERANGE).
bool currentDirectory(char *buffer, size_t size) noexcept;

bool changeDirectory(const char *path) noexcept;

// A directory that everyone may read, write and search, less the process's
// umask, as mkdir gives any.
bool createDirectory(const char *path) noexcept;

bool removeDirectory(const char *path) noexcept;

// Faults (Posix/Faults.cpp).

// From now on a fault on memory calls onFault with the faulting address, on
// the thread's signal stack; when onFault returns, the fault gets the action
// it had before this call, as if it were never caught. onFault may only make
// async-signal-safe calls. The first call installs it, and later ones
// replace onFault.
void catchFaults(void (*onFault)(uintptr_t address)) noexcept;

// Files (Posix/Files.cpp).

// An open file: the C library's stream, which buffers it.
using File = FILE;

// fopen's: the file at a path in a mode ("r", "w+", ...), or null.
File *openFile(const char *path, const char *mode) noexcept;

// How a write went: every byte written; the reader of a pipe gone, which
// ends the program by the signal Unix tools die of; or another failure,
// which errno names.
enum class Wrote : uint8_t { Whole, Broken, Failed };

// Closes the stream, writing what it has pending, and how that went. The
// stream is gone either way.
Wrote closeFile(File *file) noexcept;

int descriptor(File *file) noexcept;

// The stream's error indicator: a read or a write on it failed.
bool fileFailed(File *file) noexcept;

// The stream's end-of-file indicator: a read met the end of the file.
bool fileEnded(File *file) noexcept;

// The next byte, or -1 at the end of the file or on a failure, which
// fileFailed tells apart.
int32_t readByte(File *file) noexcept;

// Up to n bytes into p: fewer at the end of the file or on a failure.
size_t readFile(File *file, char *p, size_t n) noexcept;

// The bytes a write through a stream's buffer took, fewer on a failure, and
// how it went.
struct FileWrote {
  size_t count;
  Wrote how;
};

// The n bytes at p, through the stream's buffer.
FileWrote writeFile(File *file, const char *p, size_t n) noexcept;

Wrote flushFile(File *file) noexcept;

bool removeFile(const char *path) noexcept;

bool changeMode(const char *path, int64_t mode) noexcept;

// The size in bytes of what the descriptor names, or -1.
int64_t fileSize(int fd) noexcept;

// A file's times, one per field of the specification's: the seconds and
// the nanoseconds since the epoch of its last access, modification and
// status change.
using FileTimes = idr::EnumArray<idr::files::FileTimeField, int64_t>;

// The times of what the descriptor names, as the one call of the system
// gives them; false when they cannot be read.
bool fileTimes(int fd, FileTimes &times) noexcept;

// A stat's times of last access, modification and status change, read by
// the names the operating system gives its fields (the operating system's
// unit).
struct StatTimes {
  struct timespec access, modified, changed;
};
StatTimes statTimes(const struct stat &status) noexcept;

// Whether the descriptor has input ready, waiting up to a second for it, as
// base's fPoll does in C: 1 when it has, 0 when the second passed, -1 on a
// failure. A descriptor select cannot watch is a failure too.
int64_t waitForInput(int fd) noexcept;

bool isTerminal(int fd) noexcept;

// Writes the n bytes at p to the descriptor, looping over partial writes; a
// failed write abandons the rest. Standard output's buffer, standard error,
// and every message an ending writes go through it.
IDRIS_RT_BASELINE Wrote writeAll(int fd, const char *p, size_t n) noexcept;

// Up to n bytes from the descriptor into p, as one read gives them: their
// count, 0 at the end of its input, or -1 when the read failed (lastError
// says why).
int64_t readSome(int fd, char *p, size_t n) noexcept;

// Memory (Posix/Memory.cpp, and the operating system's unit).

// The size of a page, which a guard and a region are multiples of: the
// target entry's (IDRIS_RT_PAGE_SIZE, CMakeLists.txt), a constant, so that
// rounding to it folds. The start of every host of the runtime compares it
// with the system's (systemPageSize) before anything uses it.
constexpr size_t pageSize() noexcept { return IDRIS_RT_PAGE_SIZE; }

// `n` rounded up to a multiple of `unit`. The caller keeps `n + unit - 1`
// from wrapping. A page is one unit; so is an alignment or a chunk that is
// a power of two, for which this is the same as masking.
constexpr size_t roundUp(size_t n, size_t unit) noexcept { return (n + unit - 1) / unit * unit; }

// The page of the process's address space, which mmap and mprotect round
// to. Compiled for the target's baseline: it is read before the processor
// test.
IDRIS_RT_BASELINE size_t systemPageSize() noexcept;

// Address space and memory are two states: a reservation is address space
// alone, inaccessible, which no host counts as memory; a commit makes pages
// of it readable and writable, which a strict host counts, and may refuse.
//
// `size` bytes of address space wherever the system places them, or null
// when it grants none.
char *reserve(size_t size) noexcept;

// What a reservation at a fixed address found: the place reserved, another
// mapping already there (the address space is shared with the C library's
// and the program's image), or the system refusing more address space.
enum class Placed : uint8_t { Reserved, Occupied, Refused };

// `size` bytes of address space at exactly `at`, never over a mapping that
// is there (the operating system's unit).
Placed reserveAt(char *at, size_t size) noexcept;

// Makes the n bytes at p, whole pages of a reservation, readable and
// writable; false when the system refuses the memory.
bool commit(char *p, size_t n) noexcept;

// Gives the `size` bytes of address space at p back.
void release(char *p, size_t size) noexcept;

// The host's facts (the operating system's unit), each read once, at start.

// The address range the heap's chunks are reserved in, in order: from an
// address aligned to `alignment`, where the host's address space is free
// above, to as far as the host lets the process map, its address-space
// limit included. Nothing of it is reserved here.
struct Span {
  char *base;
  size_t length;
};
Span heapSpan(size_t alignment) noexcept;

// The directory the host's own files are read under: the filesystem's root,
// for every program and tool. A test reads a tree it planted under another
// (idris_rt_commit_limit), so the reader is tested on every target, and on
// limits no host of the test's holds.
inline constexpr const char *hostRoot = "";

// The bytes of memory the process may still commit before the host kills
// it, the operating system's unit's: what its host's cgroup states on
// Linux; SIZE_MAX on Darwin, which states none.
size_t commitLimit() noexcept;

// The bytes of memory a process may still commit before the kernel's killer
// ends it, as a Linux host's cgroup files under `root` state it: the lowest
// limit on the way from the process's group to its hierarchy's mount, with
// the swap that group may use, less what the group holds already; SIZE_MAX
// where none holds. It reads files alone (Posix/Cgroups.cpp), so it is the
// same reader on every target.
size_t cgroupLimit(const char *root) noexcept;

// The bytes of physical memory the system has.
size_t physicalMemory() noexcept;

// The bytes the process may map in all, its address-space limit (`ulimit
// -v`, Posix/Memory.cpp), which counts every mapping; SIZE_MAX where none
// holds.
size_t addressSpaceLimit() noexcept;

// The bytes the system's delivery of a signal takes on a signal stack, its
// own frame for the handler: the host's, which a processor with wider
// registers makes larger than any constant of the C library.
size_t signalStackMinimum() noexcept;

// The bytes a thread of the C library keeps at the top of a stack it is
// given, its own descriptor and thread-local storage.
size_t threadStackMinimum() noexcept;

// The process (Posix/Process.cpp).

// What the last failing call of the C library left in errno.
int lastError() noexcept;

// strerror's text of an error number, valid until the next call.
const char *errorText(int code) noexcept;

// The value of an environment variable, valid until the environment
// changes, or null when it is not set.
const char *environment(const char *name) noexcept;

// The environment's `name=value` entry at an index, valid until the
// environment changes, or null when there is none.
const char *environmentEntry(int64_t index) noexcept;

// What setting a variable that is already set does: its value stays, or the
// new one replaces it. Each case is the value setenv's third argument
// takes for it.
enum class WhenSet : int { Keep = 0, Replace = 1 };

bool setEnvironment(const char *name, const char *value, WhenSet set) noexcept;

bool unsetEnvironment(const char *name) noexcept;

// Waits that long, or until a signal interrupts the wait; false when it was
// cut short or the time is not one nanosleep takes.
bool sleepFor(int64_t seconds, int64_t nanoseconds) noexcept;

int64_t secondsSinceEpoch() noexcept;

int64_t processId() noexcept;

// Ends the process with the status at once: no handler runs and no stream of
// the C library is written.
[[noreturn]] IDRIS_RT_BASELINE void exitProcess(int status) noexcept;

// A write to a pipe whose reader went away fails, rather than killing the
// process before it can write its other files: the runtime then ends it by
// the same signal itself (raiseSignal), once they are written.
void ignoreBrokenPipes() noexcept;

// Ends the process by the signal, as its default action takes it: SIGABRT
// for an internal error, SIGPIPE for a reader gone. Async-signal-safe.
[[noreturn]] void raiseSignal(idr::endings::EndingSignal signal) noexcept;

// Processors (Posix/Processors.cpp).

// The number of processors online, from the system, at the moment it is
// asked. -1 when the system does not say.
int64_t nprocessors() noexcept;

// Stacks (Posix/Stacks.cpp).

// Runs fn(arg) on a new thread whose stack is the `size` bytes at `stack`,
// and returns once it has; false when no thread could start, and fn did
// not run.
bool runThread(void (*fn)(void *), void *arg, char *stack, size_t size) noexcept;

// Makes the n bytes at p the calling thread's stack for signal handlers.
void useSignalStack(char *p, size_t n) noexcept;

// The calling thread has no stack for signal handlers any more.
void dropSignalStack() noexcept;

// A stack's guard: a fault at an address in [low, high) is its thread
// reaching the end of its stack.
struct Guard {
  uintptr_t low;
  uintptr_t high;
  bool holds(uintptr_t address) const noexcept { return address >= low && address < high; }
};

// Each thread's guard, where the fault handler finds it on the thread a
// fault is met on: keepGuard makes `guard` the calling thread's (null for
// none), keptGuard reads it (null on a thread that kept none), and `atEnd`
// takes one still kept when its thread ends. guardsEnd is called before a
// second thread runs; false when the system has no slot left for it.
bool guardsEnd(void (*atEnd)(Guard *guard)) noexcept;
void keepGuard(Guard *guard) noexcept;
Guard *keptGuard() noexcept;

// The guard the C library placed below the calling thread's stack when it
// made the thread, as the operating system's unit reads it.
Guard libraryGuard() noexcept;

// The terminal (Posix/Terminal.cpp).

// Standard input without echo and without line editing, so a read sees each
// byte as it is typed; false when its mode cannot be read or set.
bool rawMode() noexcept;

// Puts back the mode raw mode replaced; nothing when it never ran.
void restoreMode() noexcept;

// The terminal's columns and rows, from standard input's terminal or else
// standard output's; false when neither is one.
bool terminalSize(int64_t &columns, int64_t &rows) noexcept;

} // namespace rt::platform
