// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// rt::platform: what the runtime asks of the operating system and the
// processor, behind one interface whose implementations a target entry
// (CMakeLists.txt) picks: Platform/Posix's serve every POSIX system, and
// each processor has its own file for its features (Platform/X86_64,
// Platform/Aarch64). Where Linux and macOS differ, one function of
// Platform/Posix holds the difference, chosen by the target's macros.
//
// What runs before the processor test (the page-size check, the test, and
// what they write and how they end the process) is marked
// idris-rt-baseline: idris-mlir keeps such a function compiled for the
// target's baseline, where it raises every other to the program's CPU.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include <dirent.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#include <string_view>

namespace rt::platform {

// Clocks (Posix/Clocks.cpp).

// The clocks base's ClockType names: the time since some point in the past,
// the time since the epoch, and the CPU time of the process and of the
// calling thread.
enum class Clock { Monotonic, Utc, Process, Thread };

// The clock's reading; false when the system cannot read it.
bool readClock(Clock clock, int64_t &seconds, int64_t &nanoseconds) noexcept;

// The processor (the target entry's Cpu.cpp).

// The IDRIS_RT_CPU_FEATURES bits of the features this processor has and
// the operating system supports. It is compiled for the target's baseline
// and kept there (the annotation idris-rt-baseline), since it runs before
// anything shows that the processor has more.
uint64_t cpuFeatures() noexcept;

// Whether this processor runs simdutf's implementation `name`: whether it
// has every feature that implementation's kernels are compiled with (their
// target attribute), tested as cpuFeatures tests the program's. This is the
// one decision of which kernels may run: simdutf's own detection, which
// tests fewer features than its kernels use, is never asked
// (Strings/Simd.cpp). False for a name the processor has no test for.
bool runsSimdutf(std::string_view name) noexcept;

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

// Closes the stream, writing what it has pending; false when that failed.
// The stream is gone either way.
bool closeFile(File *file) noexcept;

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

// The n bytes at p, through the stream's buffer: fewer on a failure.
size_t writeFile(File *file, const char *p, size_t n) noexcept;

bool flushFile(File *file) noexcept;

bool removeFile(const char *path) noexcept;

bool changeMode(const char *path, int64_t mode) noexcept;

// The size in bytes of what the descriptor names, or -1.
int64_t fileSize(int fd) noexcept;

// The access, modification and status change times of what the descriptor
// names, each as seconds and nanoseconds, in that order; false when they
// cannot be read.
bool fileTimes(int fd, int64_t (&times)[6]) noexcept;

// Whether the descriptor has input ready, waiting up to a second for it, as
// base's fPoll does in C: 1 when it has, 0 when the second passed, -1 on a
// failure. A descriptor select cannot watch is a failure too.
int64_t waitForInput(int fd) noexcept;

bool isTerminal(int fd) noexcept;

// Writes the n bytes at p to the descriptor, looping over partial writes; a
// failed write abandons the rest. Standard output's buffer, standard error,
// and every message before the program runs go through it.
[[clang::annotate("idris-rt-baseline")]] void writeAll(int fd, const char *p, size_t n) noexcept;

// Up to n bytes from the descriptor into p, as one read gives them: their
// count, 0 at the end of its input, or -1 when the read failed (lastError
// says why).
int64_t readSome(int fd, char *p, size_t n) noexcept;

// Memory (Posix/Memory.cpp).

// The size of a page, which a guard and a region are multiples of: the
// target entry's (IDRIS_RT_PAGE_SIZE, CMakeLists.txt), a constant, so that
// rounding to it folds. checkPageSize below makes it the system's before
// anything uses it: the program's entry and the reserved-stack runner call
// it first.
constexpr size_t pageSize() noexcept { return IDRIS_RT_PAGE_SIZE; }

// `n` rounded up to a multiple of `unit`. The caller keeps `n + unit - 1`
// from wrapping. A page is one unit; so is an alignment or a chunk that is
// a power of two, for which this is the same as masking.
constexpr size_t roundUp(size_t n, size_t unit) noexcept { return (n + unit - 1) / unit * unit; }

// Ends the process, naming both, when the target entry's page size is not
// the system's.
void checkPageSize() noexcept;

// `size` bytes of address space, readable and writable and committed as
// they are touched, starting at a multiple of `alignment`, or null when the
// system grants none that large. The alignment is a power of two, a page or
// more; the caller keeps `size + alignment` from wrapping.
char *reserve(size_t size, size_t alignment = pageSize()) noexcept;

// Makes the n bytes at p, whole pages, inaccessible.
bool protect(char *p, size_t n) noexcept;

// Gives the `size` bytes of address space at p back.
void release(char *p, size_t size) noexcept;

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

bool setEnvironment(const char *name, const char *value, bool overwrite) noexcept;

bool unsetEnvironment(const char *name) noexcept;

// Waits that long, or until a signal interrupts the wait; false when it was
// cut short or the time is not one nanosleep takes.
bool sleepFor(int64_t seconds, int64_t nanoseconds) noexcept;

int64_t secondsSinceEpoch() noexcept;

int64_t processId() noexcept;

// Ends the process with the status at once: no handler runs and no stream of
// the C library is written.
[[noreturn, clang::annotate("idris-rt-baseline")]] void exitProcess(int status) noexcept;

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

// The process's stack limit in bytes: SIZE_MAX when it has none, which is
// larger than any, and 0 when it cannot be read, which raises nothing.
size_t stackLimit() noexcept;

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
