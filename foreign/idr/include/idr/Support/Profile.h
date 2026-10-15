// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Profiling with LLVM's time trace: the one header that includes it.
// Every build compiles these macros; nothing is a special build. A trace
// is a run-time choice, --time-trace=<file> on a tool, as clang's
// -ftime-trace is: until a tool starts one, the profiler is not
// initialized and a zone is a load and a branch, so nothing is recorded
// and no output byte changes. The trace is Chrome trace JSON, read by
// Perfetto. The zones of passes and analyses, whose names are only
// known at run time, are addInstrumentation's and llvmCallbacks'.
#ifndef IDR_SUPPORT_PROFILE_H
#define IDR_SUPPORT_PROFILE_H

#include "llvm/ADT/StringRef.h"
#include "llvm/Support/TimeProfiler.h"

#include <string>

namespace llvm {
class PassInstrumentationCallbacks;
} // namespace llvm

namespace mlir {
class PassManager;
} // namespace mlir

namespace idr::profile {

// One tool's trace, from its command line to its exit: constructed after
// the options are read, it starts the profiler when --time-trace named
// a file (--time-trace-granularity=<microseconds> coarsens it; at 0, the
// default, every span is kept), and its destruction writes the trace.
// Constructing one in a tool that was not asked for a trace does nothing.
struct Trace {
  explicit Trace(llvm::StringRef procName);
  ~Trace();
  Trace(const Trace &) = delete;
  Trace &operator=(const Trace &) = delete;
};

// A worker thread's share of the trace, for a thread a tool spawns and
// joins itself (the driver's large-stack thread) and for a task a pass or
// the driver runs on a pool itself (a function of idr-optimize's ready
// set, a bin's code generation), constructed at the task's top: the
// profiler's state is a thread's own, and no pool begins it, so a task
// begins its thread's where it has none and finishes only what it began,
// and the process's Trace writes them all. The pipelines the pass manager
// runs on its threads are addInstrumentation's.
struct ThreadTrace {
  ThreadTrace();
  ~ThreadTrace();
  ThreadTrace(const ThreadTrace &) = delete;
  ThreadTrace &operator=(const ThreadTrace &) = delete;

  bool owns = false;
};

// Zones for every pass and every analysis the manager runs, named by the
// pass or analysis. Defined in every build; while no trace is started
// its hooks record nothing, so a manager's owner calls it
// unconditionally.
void addInstrumentation(mlir::PassManager &pm);

// The callbacks that give every pass and every analysis of an LLVM
// pipeline its zone, for llvm::PassBuilder, which takes them as a
// pointer it may be given or not. Null while no trace is started, so a
// builder given it is then the builder it was.
llvm::PassInstrumentationCallbacks *llvmCallbacks();

} // namespace idr::profile

// A zone is a TimeTraceScope, whose variable the line names. The
// subsystem a zone belongs to is its caller's to state, for a reader;
// the trace format has no colours to give it.
#define IDR_ZONE_INNER(name, line) llvm::TimeTraceScope idr_time_trace_scope_##line(name)
#define IDR_ZONE_EXPAND(name, line) IDR_ZONE_INNER(name, line)
#define IDR_ZONE(name) IDR_ZONE_EXPAND(name, __LINE__)
#define IDR_ZONE_IN(name, subsystem) IDR_ZONE(name)
// A point in a trace, where one stage of a thing (a compilation) ends:
// the format's instant event.
#define IDR_INSTANT(name) llvm::timeTraceAddInstantEvent(name, [] { return std::string(); })

#endif // IDR_SUPPORT_PROFILE_H
