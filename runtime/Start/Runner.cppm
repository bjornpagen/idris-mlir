// rt.start:runner: running a function on a reserved stack, behind a guard
// whose fault is the stack running out.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

export module rt.start:runner;

import rt.platform;

namespace {

// The runner's state, which the fault handler reads. One runner runs at a
// time in a process: the program's, idris-mlir-cc's, or, after a fork, the
// evaluation child's, which replaces its parent's.
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
// crash report in idris-mlir-cc, runs on it too.
constexpr size_t alternateSize = size_t{1} << 20;
constexpr size_t smallest = size_t{1} << 26;

size_t roundUp(size_t n, size_t page) { return (n + page - 1) / page * page; }

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

extern "C" int idris_rt_run_on_stack(void (*fn)(void *), void *arg, size_t most, size_t guard,
                                     void (*exhausted)(void)) {
  size_t page = rt::platform::pageSize();
  size_t alternate = roundUp(alternateSize, page);
  guard = roundUp(guard, page);
  size_t size = roundUp(most, page);
  size_t least = size < smallest ? size : smallest;
  if (least < page)
    least = page;
  for (; size >= least; size = size / 2 / page * page) {
    size_t region = alternate + guard + size;
    char *base = rt::platform::reserve(region);
    if (base == nullptr)
      continue;
    if (!rt::platform::protect(base + alternate, guard)) {
      rt::platform::release(base, region);
      continue;
    }
    guardLow = reinterpret_cast<uintptr_t>(base + alternate);
    guardHigh = guardLow + guard;
    onExhausted = exhausted;
    rt::platform::catchFaults(onFault);
    Task task{fn, arg, base, alternate};
    bool ran = rt::platform::runThread(runTask, &task, base + alternate + guard, size);
    guardLow = guardHigh = 0;
    rt::platform::release(base, region);
    if (ran)
      return 0;
  }
  return -1;
}
