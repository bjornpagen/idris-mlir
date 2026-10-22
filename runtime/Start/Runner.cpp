// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Running a function on a stack of its known size, behind a guard whose
// fault is the runtime's internal error, with a signal stack of its own
// behind a guard of its own; and the heap set up before it, once.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "End/End.h"
#include "Platform/Platform.h"
#include "Start/Start.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace {

// The stack's guard, which the fault handler reads. One runner runs at a
// time in a process: the program's or a tool's.
uintptr_t guardLow = 0;
uintptr_t guardHigh = 0;

// A fault on the stack's guard: the compiler sized the stack from every
// frame the code on it can stack, so reaching the guard is its bug, or the
// runtime's. Any other fault is not the runner's, and returning gives it the
// action it had before.
void onFault(uintptr_t address) {
  if (address >= guardLow && address < guardHigh)
    rt::end::end(rt::end::StackExhausted{});
}

struct Task {
  void (*fn)(void *);
  void *arg;
  char *signalStack;
  size_t signalSize;
};

// snmalloc makes a thread's allocator with its first allocation, and meets
// a failure of that one as its own fatal error rather than as an
// allocation's: one allocation here, before fn, moves it before anything
// of the program's runs.
void runTask(void *argument) {
  auto &task = *static_cast<Task *>(argument);
  rt::platform::useSignalStack(task.signalStack, task.signalSize);
  rt::alloc::release(rt::alloc::allocate(1));
  task.fn(task.arg);
}

// `a + b` rounded up to whole pages, or false where it wraps.
bool pages(size_t a, size_t b, size_t &rounded) {
  constexpr size_t page = rt::platform::pageSize();
  size_t sum;
  if (__builtin_add_overflow(a, b, &sum) || __builtin_add_overflow(sum, page - 1, &sum))
    return false;
  rounded = sum / page * page;
  return true;
}

} // namespace

idris_rt_ran rt::start::run(void (*fn)(void *), void *arg, const idris_rt_stack_plan &plan,
                            size_t limit) noexcept {
  if (!rt::alloc::initialise(limit))
    return IDRIS_RT_REFUSED;
  pointGmp();
  // Each part a whole number of pages: the guard at least a page and at
  // least the largest frame, so no frame steps over it; the stack and the
  // signal stack what the plan says, with what the host's thread and its
  // signal delivery take on them.
  size_t guard, stack, signal, region;
  if (!pages(plan.frame_bytes > 0 ? plan.frame_bytes : 1, 0, guard) ||
      !pages(plan.stack_bytes, rt::platform::threadStackMinimum(), stack) ||
      !pages(plan.signal_bytes, rt::platform::signalStackMinimum(), signal) ||
      __builtin_add_overflow(guard * 2, stack, &region) ||
      __builtin_add_overflow(region, signal, &region))
    return IDRIS_RT_REFUSED;
  char *base = rt::alloc::reserveFirst(region);
  if (base == nullptr)
    return IDRIS_RT_REFUSED;
  char *stackLow = base + guard;
  char *signalLow = stackLow + stack + guard;
  if (!rt::platform::commit(stackLow, stack) || !rt::platform::commit(signalLow, signal)) {
    rt::platform::release(base, region);
    return IDRIS_RT_REFUSED;
  }
  guardLow = reinterpret_cast<uintptr_t>(base);
  guardHigh = guardLow + guard;
  rt::platform::catchFaults(onFault);
  Task task{fn, arg, signalLow, signal};
  bool ran = rt::platform::runThread(runTask, &task, stackLow, stack);
  guardLow = guardHigh = 0;
  rt::platform::release(base, region);
  return ran ? IDRIS_RT_RAN : IDRIS_RT_REFUSED;
}

// The tools' runner: their stack is their build's measured need (idris-mlir
// and its sibling tools pass it), their name the one every message of the
// runtime's begins with, the processor features their code was compiled to
// use (the runtime's native code calls the target's simdutf kernels, whose
// features are the program CPU's), and their heap bounded by nothing but
// the machine. The tools run here without idris_rt_start, so it passes
// the same startup check first.
extern "C" idris_rt_ran idris_rt_run_on_stack(void (*fn)(void *), void *arg,
                                              const idris_rt_stack_plan *plan, const char *name,
                                              size_t name_bytes, uint64_t cpu_features) {
  rt::end::name(name, name_bytes);
  rt::start::checkMachine(cpu_features);
  return rt::start::run(fn, arg, *plan, SIZE_MAX);
}

// The memory a tool may plan for: the system's physical memory, no more
// than the process may map (its address-space limit) or still commit
// before the host kills it (its cgroup's limit).
extern "C" uint64_t idris_rt_host_memory(void) {
  size_t bytes = rt::platform::physicalMemory();
  size_t space = rt::platform::addressSpaceLimit();
  size_t commit = rt::platform::commitLimit(rt::platform::hostRoot);
  if (space < bytes)
    bytes = space;
  if (commit < bytes)
    bytes = commit;
  return bytes;
}

// The bytes the process may still commit before its host kills it, read
// from the host's files under `root`: "" for the host's own, a directory a
// test planted a host's tree in (its proc/self/cgroup, proc/self/mountinfo
// and the cgroup hierarchy they name) otherwise; UINT64_MAX where no limit
// holds.
extern "C" uint64_t idris_rt_commit_limit(const char *root) {
  return rt::platform::commitLimit(root);
}
