// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Profiling with LLVM's time trace: the one header that includes it.
// Every build compiles these macros; nothing is a special build. A trace
// is a run-time choice, --time-trace=<file> on a tool, as clang's
// -ftime-trace is: until a tool starts one, the profiler is not
// initialized and a zone is a load and a branch, so nothing is recorded
// and no output byte changes. The trace is Chrome trace JSON, read by
// Perfetto. The zones of passes and analyses, whose names are only
// known at run time, are addInstrumentation's and llvmCallbacks'; each
// pass's footprint, run by run, is footprints', handed to whoever records
// it (the driver's report).
#ifndef IDR_SUPPORT_PROFILE_H
#define IDR_SUPPORT_PROFILE_H

#include "idr/Support/Footprint.h"

#include "mlir/Pass/PassInstrumentation.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/Threading.h"
#include "llvm/Support/TimeProfiler.h"

#include <concepts>
#include <cstdint>
#include <memory>
#include <string>
#include <utility>

namespace llvm {
class PassInstrumentationCallbacks;
} // namespace llvm

namespace mlir {
class PassManager;
} // namespace mlir

namespace idr::profile {

// Whether a scope began its thread's profiler, and so finishes it, or found
// one already begun by an outer scope.
enum class Profiler : std::uint8_t { Inherited, Begun };

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

private:
  Profiler profiler = Profiler::Inherited;
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

namespace detail {

// The pass manager calls a run's before- and after-hooks on the one thread
// that runs it, in nesting order, so the runs a thread is inside are a
// stack of that thread's. Which thread runs a pass is known only when it
// runs, so the stack is found by the thread's id; the manager calls every
// instrumentation's hooks under its one lock, so the map needs none of its
// own, and it lives as long as the manager that owns this instrumentation.
template <class Record>
class Footprints final : public mlir::PassInstrumentation {
public:
  explicit Footprints(Record record) : record(std::move(record)) {}

  void runBeforePass(mlir::Pass *, mlir::Operation *) override {
    runs[llvm::get_threadid()].push_back(footprint::Run::begin());
  }
  void runAfterPass(mlir::Pass *pass, mlir::Operation *) override { end(*pass); }
  void runAfterPassFailed(mlir::Pass *pass, mlir::Operation *) override { end(*pass); }

private:
  void end(mlir::Pass &pass) { record(pass, runs[llvm::get_threadid()].pop_back_val().end()); }

  Record record;
  // Each thread's runs, innermost last.
  llvm::DenseMap<std::uint64_t, llvm::SmallVector<footprint::Run, 4>> runs;
};

} // namespace detail

// The footprint of every run of every pass a manager runs, those of its
// nested and dynamic pipelines included (footprint::Run): `record` is given
// the pass and the bytes as each run ends, on the thread that ran it, which
// may be any of the manager's, so what it writes into is its own to lock.
template <class Record>
  requires std::invocable<Record &, mlir::Pass &, std::uint64_t>
std::unique_ptr<mlir::PassInstrumentation> footprints(Record record) {
  return std::make_unique<detail::Footprints<Record>>(std::move(record));
}

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
