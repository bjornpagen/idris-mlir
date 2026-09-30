// What the runtime asks of the operating system and the processor, behind
// one interface: a target entry (CMakeLists.txt) picks the files that
// implement it. platform_posix.cc serves every POSIX system; each
// processor has its own file for its features (cpu_x86_64.cc).
// PIN(runtime-quarantine) — see PINS.md

#pragma once

#include <stddef.h>
#include <stdint.h>

namespace rt::platform {

// The size of a page, which a guard and a region are multiples of.
size_t pageSize() noexcept;

// `size` bytes of address space, readable and writable and committed as
// they are touched, or null when the system grants none that large.
char *reserve(size_t size) noexcept;
// Makes the n bytes at p, whole pages, inaccessible.
bool protect(char *p, size_t n) noexcept;
void release(char *p, size_t size) noexcept;

// Runs fn(arg) on a new thread whose stack is the `size` bytes at `stack`,
// and returns once it has; false when no thread could start, and fn did
// not run.
bool runThread(void (*fn)(void *), void *arg, char *stack, size_t size) noexcept;

// Makes the n bytes at p the calling thread's stack for signal handlers.
void useSignalStack(char *p, size_t n) noexcept;

// From now on a fault on memory calls onFault with the faulting address, on
// the thread's signal stack; when onFault returns, the fault gets the action
// it had before this call, as if it were never caught. onFault may only make
// async-signal-safe calls. The first call installs it, and later ones
// replace onFault.
void catchFaults(void (*onFault)(uintptr_t address)) noexcept;

// The process's stack limit in bytes: SIZE_MAX when it has none, 0 when it
// cannot be read.
size_t stackLimit() noexcept;

// The IDRIS_RT_CPU_FEATURES bits of the features this processor has and
// the operating system supports. It is compiled for the target's baseline
// and kept there (the annotation idris-rt-baseline), since it runs before
// anything shows that the processor has more.
uint64_t cpuFeatures() noexcept;

} // namespace rt::platform
