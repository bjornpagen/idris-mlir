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

// What code outside the compiled code takes on a stack below any of its
// frames, which no compiler sizes: the C library's, GMP's and compiler-rt's
// frames, measured for the target and kept in its entry (CMakeLists.txt).
// One margin, which the runner adds to a program's plan and a tool's alike.
#ifndef IDRIS_RT_OUTSIDE_STACK_BYTES
#error "the target entry gives the stack outside code takes (IDRIS_RT_OUTSIDE_STACK_BYTES)"
#endif

namespace {

constexpr size_t outsideBytes = IDRIS_RT_OUTSIDE_STACK_BYTES;

// What the runner gave its thread, kept while fn runs, which a tool's other
// threads take too: the guard, the stack, and the signal stack's need (the
// plan's with the host's own part) before it is rounded to pages. One
// runner runs at a time in a process: the program's or a tool's.
struct Sizes {
  size_t guard, stack, signal;
};
Sizes kept{};

// A fault on its thread's stack guard: the compiler sized the stack from
// every frame the code on it can stack, so reaching the guard is its bug,
// or the runtime's. Any other fault is not the runner's, and returning gives
// it the action it had before.
void onFault(uintptr_t address) {
  if (const rt::platform::Guard *guard = rt::platform::keptGuard();
      guard != nullptr && guard->holds(address))
    rt::end::end(rt::end::StackExhausted{});
}

// A thread a tool's pool starts, as idris_rt_start_thread sets it up: the
// guard the C library put below its stack, which is what the thread keeps,
// and the region of its signal stack, given back when the thread ends. It
// lies at the region's top.
struct alignas(16) Worker {
  rt::platform::Guard guard;
  char *region;
  size_t bytes;
};
static_assert(offsetof(Worker, guard) == 0, "a worker's kept guard is the worker");

// A worker ends: its signal stack is dropped before its region, the record
// with it, goes back.
void endWorker(rt::platform::Guard *guard) {
  auto *worker = reinterpret_cast<Worker *>(guard);
  rt::platform::dropSignalStack();
  rt::platform::release(worker->region, worker->bytes);
}

struct Task {
  void (*fn)(void *);
  void *arg;
  char *signalStack;
  size_t signalSize;
  rt::platform::Guard guard;
};

// snmalloc makes a thread's allocator with its first allocation, and meets
// a failure of that one as its own fatal error rather than as an
// allocation's: one allocation here, before fn, moves it before anything
// of the program's runs. The task's guard lies in the runner's region,
// which run gives back, so the thread keeps it only while fn runs.
void runTask(void *argument) {
  auto &task = *static_cast<Task *>(argument);
  rt::platform::useSignalStack(task.signalStack, task.signalSize);
  rt::platform::keepGuard(&task.guard);
  rt::alloc::release(rt::alloc::allocate(1));
  task.fn(task.arg);
  rt::platform::keepGuard(nullptr);
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
  // signal stack what the plan says, with what outside code, the host's
  // thread and its signal delivery take on them.
  size_t guard, own, stack, need, signal, region;
  if (!pages(plan.frame_bytes > 0 ? plan.frame_bytes : 1, 0, guard) ||
      __builtin_add_overflow(plan.stack_bytes, outsideBytes, &own) ||
      !pages(own, rt::platform::threadStackMinimum(), stack) ||
      __builtin_add_overflow(plan.signal_bytes, outsideBytes, &need) ||
      __builtin_add_overflow(need, rt::platform::signalStackMinimum(), &need) ||
      !pages(need, 0, signal) || __builtin_add_overflow(guard * 2, stack, &region) ||
      __builtin_add_overflow(region, signal, &region) || !rt::platform::guardsEnd(endWorker))
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
  kept = {guard, stack, need};
  rt::platform::catchFaults(onFault);
  auto low = reinterpret_cast<uintptr_t>(base);
  Task task{fn, arg, signalLow, signal, {low, low + guard}};
  bool ran = rt::platform::runThread(runTask, &task, stackLow, stack);
  kept = {};
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

// The size the runner gave its thread, kept: a tool's other threads take
// it, and never read the host's part again.
extern "C" uint64_t idris_rt_thread_stack_bytes(void) { return kept.stack; }

// A tool's worker, on it, as it starts: a signal stack of the runner's
// thread's need behind a guard as large as its, the worker's record above
// it; and the C library's guard below the worker's stack kept as the
// thread's, so reaching it ends the tool as reaching the runner's guard
// does. Nothing wraps: run fitted the runner's two guards, stack and signal
// stack, rounded, in one region, and this is less.
extern "C" void idris_rt_start_thread(void) {
  size_t signal = rt::platform::roundUp(kept.signal + sizeof(Worker), rt::platform::pageSize());
  size_t bytes = kept.guard + signal;
  char *region = rt::platform::reserve(bytes);
  if (region == nullptr || !rt::platform::commit(region + kept.guard, signal))
    rt::end::end(rt::end::OutOfMemory{});
  auto *worker = reinterpret_cast<Worker *>(region + bytes) - 1;
  *worker = Worker{rt::platform::libraryGuard(), region, bytes};
  rt::platform::useSignalStack(region + kept.guard, signal - sizeof(Worker));
  rt::platform::keepGuard(&worker->guard);
}

// The memory a tool may plan for: the system's physical memory, no more
// than the process may map (its address-space limit) or still commit
// before the host kills it (its cgroup's limit).
extern "C" uint64_t idris_rt_host_memory(void) {
  size_t bytes = rt::platform::physicalMemory();
  size_t space = rt::platform::addressSpaceLimit();
  size_t commit = rt::platform::commitLimit();
  if (space < bytes)
    bytes = space;
  if (commit < bytes)
    bytes = commit;
  return bytes;
}

// The bytes a process may still commit before its host kills it, as a
// Linux host's cgroup files under `root` state it: "" for this host's own,
// a directory a test planted a host's tree in (its proc/self/cgroup,
// proc/self/mountinfo, proc/meminfo and the cgroup hierarchy they name)
// otherwise; UINT64_MAX where no limit holds. The same reader on every
// target, so a test plants the same trees on all of them.
extern "C" uint64_t idris_rt_commit_limit(const char *root) {
  return rt::platform::cgroupLimit(root);
}
