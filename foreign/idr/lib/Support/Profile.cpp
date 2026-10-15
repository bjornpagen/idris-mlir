// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The zones of passes and analyses, on LLVM's time trace: one MLIR pass
// instrumentation on the manager of idris-mlir and of idris-mlir-opt,
// which every nested and dynamic pipeline run under it (a module pass's
// own, the one idr-optimize runs on each function) inherits, and one set of LLVM pass
// instrumentation callbacks for the optimizer's pipeline, so every pass
// and every analysis on either side gets its zone here and no pass adds
// one for its run. A zone opened in a before-hook closes in the matching
// after-hook, a call later, so no scope can hold it; each side calls a
// pass's or analysis's before- and after-hooks on the one thread that
// runs it, in nesting order, which is the order the profiler's per-thread
// stack keeps.
//
// The profiler's state is a thread's own, and a pass manager runs its
// nested pipelines on its context's pool threads. So a pipeline hook
// begins the calling thread's profiler where it has none and finishes it
// where the outermost pipeline on that thread ends, and the finished
// threads' entries are written with the process's. A pipeline a pass
// failed in never runs its after-pipeline hook (Pass.cpp returns first),
// so the failing pass's after-hook finishes the thread instead.
//
// Nothing here is compiled away: until a tool starts a trace with
// --time-trace, no thread's profiler exists and every hook but the
// pipeline ones is a load and a branch, which is what -mlir-timing's
// instrumentations cost untimed too.

#include "idr/Support/Profile.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Support/TypeID.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallString.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/IRUnitRef.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/PassInstrumentation.h"
#include "llvm/Support/Casting.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Error.h"
#include "llvm/Support/Threading.h"
#include "llvm/Support/raw_ostream.h"

#include <cstdint>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <utility>

namespace {

// The trace a tool was asked for, as clang's -ftime-trace asks: a file,
// and the shortest span worth keeping. At zero (the default) every span
// is kept; a coarser trace is the knob, never the default trade.
llvm::cl::opt<std::string> timeTraceFile(
    "time-trace", llvm::cl::value_desc("file"),
    llvm::cl::desc("Write a time trace of the compilation (every pass, analysis and "
                   "driver phase) as Chrome trace JSON to <file>, for Perfetto"));
llvm::cl::opt<unsigned> timeTraceGranularity(
    "time-trace-granularity", llvm::cl::value_desc("microseconds"), llvm::cl::init(0),
    llvm::cl::desc("With --time-trace, drop spans shorter than this many microseconds"));

// What the process's Trace started, read by every thread that begins its
// own profiler from it. It is written once, before any work that is
// traced, and only read after.
struct TraceState {
  std::string proc;
  bool started = false;
};
TraceState traceState;

// What an MLIR pass zone ran on, as its detail: the operation's name and,
// for a symbol, its name, which tells one function's run of a function
// pass from another's.
std::string describe(mlir::Operation *op) {
  llvm::SmallString<128> text(op->getName().getStringRef());
  if (auto symbol = op->getAttrOfType<mlir::StringAttr>(mlir::SymbolTable::getSymbolAttrName())) {
    text += " @";
    text += symbol.getValue();
  }
  return text.str().str();
}

// What an LLVM pass or analysis zone ran on, where the unit has a name.
std::string describe(llvm::IRUnitRef ir) {
  if (const auto *function = llvm::dyn_cast<llvm::Function>(ir))
    return function->getName().str();
  if (const auto *module = llvm::dyn_cast<llvm::Module>(ir))
    return module->getName().str();
  return {};
}

void beginLlvmZone(llvm::StringRef name, llvm::IRUnitRef ir) {
  llvm::timeTraceProfilerBegin(name, [ir] { return describe(ir); });
}

void endLlvmZone() {
  if (llvm::getTimeTraceProfilerInstance())
    llvm::timeTraceProfilerEnd();
}

class Zones final : public mlir::PassInstrumentation {
public:
  void runBeforePipeline(std::optional<mlir::OperationName>, const PipelineParentInfo &) override {
    if (!traceState.started)
      return;
    std::uint64_t thread = llvm::get_threadid();
    std::lock_guard<std::mutex> lock(mutex);
    unsigned &depth = depths[thread];
    if (depth == 0 && !llvm::getTimeTraceProfilerInstance()) {
      llvm::timeTraceProfilerInitialize(timeTraceGranularity, traceState.proc);
      owned.insert(thread);
    }
    ++depth;
  }

  void runAfterPipeline(std::optional<mlir::OperationName>, const PipelineParentInfo &) override {
    leavePipeline(false);
  }

  void runBeforePass(mlir::Pass *pass, mlir::Operation *op) override {
    // The name is the one -mlir-timing prints.
    llvm::timeTraceProfilerBegin(pass->getName(), [op] { return describe(op); });
  }

  void runAfterPass(mlir::Pass *, mlir::Operation *) override {
    if (llvm::getTimeTraceProfilerInstance())
      llvm::timeTraceProfilerEnd();
  }

  void runAfterPassFailed(mlir::Pass *, mlir::Operation *) override {
    if (llvm::getTimeTraceProfilerInstance())
      llvm::timeTraceProfilerEnd();
    // A failed pipeline skips its after-pipeline hook, so this thread's
    // pipelines are all unwinding: finish its profiler here.
    leavePipeline(true);
  }

  void runBeforeAnalysis(llvm::StringRef name, mlir::TypeID, mlir::Operation *op) override {
    llvm::timeTraceProfilerBegin(name, [op] { return describe(op); });
  }

  void runAfterAnalysis(llvm::StringRef, mlir::TypeID, mlir::Operation *) override {
    if (llvm::getTimeTraceProfilerInstance())
      llvm::timeTraceProfilerEnd();
  }

private:
  void leavePipeline(bool failed) {
    if (!traceState.started)
      return;
    std::uint64_t thread = llvm::get_threadid();
    std::lock_guard<std::mutex> lock(mutex);
    auto found = depths.find(thread);
    if (found == depths.end())
      return;
    if (failed)
      found->second = 0;
    else if (found->second > 0)
      --found->second;
    if (found->second == 0) {
      depths.erase(found);
      if (owned.erase(thread))
        llvm::timeTraceProfilerFinishThread();
    }
  }

  std::mutex mutex;
  llvm::DenseMap<std::uint64_t, unsigned> depths;
  llvm::DenseSet<std::uint64_t> owned;
};

struct LlvmCallbacks {
  llvm::PassInstrumentationCallbacks pic;
  bool registered = false;
};
LlvmCallbacks llvmCallbacksState;

} // namespace

idr::profile::Trace::Trace(llvm::StringRef proc) : procName(proc.str()) {
  if (timeTraceFile.empty())
    return;
  traceState.proc = procName;
  traceState.started = true;
  llvm::timeTraceProfilerInitialize(timeTraceGranularity, procName);
  active = true;
}

idr::profile::Trace::~Trace() {
  if (!active)
    return;
  if (llvm::Error error = llvm::timeTraceProfilerWrite(timeTraceFile, ""))
    llvm::errs() << procName << ": cannot write the time trace to " << timeTraceFile << ": "
                 << llvm::toString(std::move(error)) << "\n";
  llvm::timeTraceProfilerCleanup();
  traceState.started = false;
}

idr::profile::ThreadTrace::ThreadTrace() {
  if (traceState.started && !llvm::getTimeTraceProfilerInstance()) {
    llvm::timeTraceProfilerInitialize(timeTraceGranularity, traceState.proc);
    owns = true;
  }
}

idr::profile::ThreadTrace::~ThreadTrace() {
  if (owns)
    llvm::timeTraceProfilerFinishThread();
}

void idr::profile::addInstrumentation(mlir::PassManager &pm) {
  pm.addInstrumentation(std::make_unique<Zones>());
}

llvm::PassInstrumentationCallbacks *idr::profile::llvmCallbacks() {
  if (!traceState.started)
    return nullptr;
  if (!llvmCallbacksState.registered) {
    llvm::PassInstrumentationCallbacks &pic = llvmCallbacksState.pic;
    pic.registerBeforeNonSkippedPassCallback(
        [](llvm::StringRef name, llvm::IRUnitRef ir) { beginLlvmZone(name, ir); });
    pic.registerAfterPassCallback(
        [](llvm::StringRef, llvm::IRUnitRef, const llvm::PreservedAnalyses &) { endLlvmZone(); });
    // The end of a pass whose IR unit it invalidated comes here instead.
    pic.registerAfterPassInvalidatedCallback(
        [](llvm::StringRef, const llvm::PreservedAnalyses &) { endLlvmZone(); });
    pic.registerBeforeAnalysisCallback(
        [](llvm::StringRef name, llvm::IRUnitRef ir) { beginLlvmZone(name, ir); });
    pic.registerAfterAnalysisCallback([](llvm::StringRef, llvm::IRUnitRef) { endLlvmZone(); });
    llvmCallbacksState.registered = true;
  }
  return &llvmCallbacksState.pic;
}
