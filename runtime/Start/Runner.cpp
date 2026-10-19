// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Running a function on a reserved stack, behind a guard whose fault is the
// stack running out.
// PIN(runtime-quarantine) — see PINS.md
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace {

// The runner's state, which the fault handler reads. One runner runs at a
// time in a process: the program's or idris-mlir's.
uintptr_t guardLow = 0;
uintptr_t guardHigh = 0;
void (*onExhausted)(void) = nullptr;

// A fault on the guard is the stack running out. Any other fault is not the
// runner's, and returning gives it the action it had before.
void onFault(uintptr_t address) {
  if (address >= guardLow && address < guardHigh)
    onExhausted();
}

// The signal handler's own stack, below the guard, so that the stack it
// reports on cannot have grown over it. A megabyte of address space, of
// which a handler touches a few pages; the action a fault had before, LLVM's
// crash report in idris-mlir, runs on it too. It is far above what any
// system asks of one (MINSIGSTKSZ and SIGSTKSZ: 32 and 128 KiB on Darwin
// arm64, a few KiB on Linux x86-64), and a whole number of pages on each.
constexpr size_t alternateSize = size_t{1} << 20;

// The inaccessible bytes below the stack: a frame larger than this could
// step over them, and none is.
constexpr size_t guardSize = size_t{1} << 20;

// The stack: 64 GiB of address space, committed only as a recursion
// touches it, which no machine we compile for fills before its memory runs
// out. A thread's stack is reserved whole when it starts, and reserving
// and releasing cost time in proportion to the size (about 0.2 ms at this
// one on Darwin, 3 ms at 1 TiB), so it is no larger.
constexpr size_t stackSize = size_t{1} << 36;

struct Task {
  void (*fn)(void *);
  void *arg;
  char *alternate;
  size_t alternateSize;
};

void runTask(void *argument) {
  auto &task = *static_cast<Task *>(argument);
  rt::platform::useSignalStack(task.alternate, task.alternateSize);
  task.fn(task.arg);
}

} // namespace

// The reserved-stack runner, which programs and idris-mlir share: runs
// fn(arg) on a new thread whose stack is stackSize bytes of reserved
// address space. Below it is a guard of inaccessible pages: a fault on the
// guard is the stack running out, and exhausted() runs, on a signal stack
// of its own, and must end the process with only async-signal-safe calls.
// Any other fault gets the action it had before. One runner runs at a time
// in a process. It checks the page size first, as idris_rt_start does: the
// compiler's tools run here without idris_rt_start. Returns 0 once fn has
// returned, or -1 when no stack could be reserved.
//
// The region is [alternate stack | guard | stack], each a whole number of
// the target's pages.
extern "C" int idris_rt_run_on_stack(void (*fn)(void *), void *arg, void (*exhausted)(void)) {
  rt::platform::checkPageSize();
  constexpr size_t page = rt::platform::pageSize();
  constexpr size_t alternate = rt::platform::roundUp(alternateSize, page);
  constexpr size_t guard = rt::platform::roundUp(guardSize, page);
  constexpr size_t size = rt::platform::roundUp(stackSize, page);
  constexpr size_t region = alternate + guard + size;
  char *base = rt::platform::reserve(region);
  if (base == nullptr)
    return -1;
  if (!rt::platform::protect(base + alternate, guard)) {
    rt::platform::release(base, region);
    return -1;
  }
  guardLow = reinterpret_cast<uintptr_t>(base + alternate);
  guardHigh = guardLow + guard;
  onExhausted = exhausted;
  rt::platform::catchFaults(onFault);
  Task task{fn, arg, base, alternate};
  bool ran = rt::platform::runThread(runTask, &task, base + alternate + guard, size);
  guardLow = guardHigh = 0;
  rt::platform::release(base, region);
  return ran ? 0 : -1;
}
