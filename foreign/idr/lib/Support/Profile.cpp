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

// The process name of the trace the process's Trace started, while it runs:
// every thread that begins its own profiler names it. It is written once,
// before any work that is traced, and only read after.
std::optional<std::string> tracedProc;

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

// A zone's end. With no profiler on the thread there is no zone, and LLVM's
// end does nothing.
void endZone() { llvm::timeTraceProfilerEnd(); }

class Zones final : public mlir::PassInstrumentation {
public:
  void runBeforePipeline(std::optional<mlir::OperationName>, const PipelineParentInfo &) override {
    if (!tracedProc)
      return;
    std::uint64_t thread = llvm::get_threadid();
    std::lock_guard<std::mutex> lock(mutex);
    // A thread enters the map at its outermost pipeline, and leaves it when
    // that pipeline ends: a depth in the map is never 0.
    auto [at, outermost] = threads.try_emplace(thread);
    if (outermost && !llvm::getTimeTraceProfilerInstance()) {
      llvm::timeTraceProfilerInitialize(timeTraceGranularity, *tracedProc);
      at->second.profiler = idr::profile::Profiler::Begun;
    }
    ++at->second.depth;
  }

  void runAfterPipeline(std::optional<mlir::OperationName>, const PipelineParentInfo &) override {
    leave([](Pipelines &pipelines) { --pipelines.depth; });
  }

  void runBeforePass(mlir::Pass *pass, mlir::Operation *op) override {
    // The name is the one -mlir-timing prints.
    llvm::timeTraceProfilerBegin(pass->getName(), [op] { return describe(op); });
  }

  void runAfterPass(mlir::Pass *, mlir::Operation *) override { endZone(); }

  void runAfterPassFailed(mlir::Pass *, mlir::Operation *) override {
    endZone();
    // A failed pipeline skips its after-pipeline hook, so this thread's
    // pipelines are all unwinding: finish its profiler here.
    leave([](Pipelines &pipelines) { pipelines.depth = 0; });
  }

  void runBeforeAnalysis(llvm::StringRef name, mlir::TypeID, mlir::Operation *op) override {
    llvm::timeTraceProfilerBegin(name, [op] { return describe(op); });
  }

  void runAfterAnalysis(llvm::StringRef, mlir::TypeID, mlir::Operation *) override { endZone(); }

private:
  // The pipelines a thread is inside, and whether its outermost began the
  // thread's profiler, which the thread then finishes when it leaves that
  // pipeline.
  struct Pipelines {
    unsigned depth = 0;
    idr::profile::Profiler profiler = idr::profile::Profiler::Inherited;
  };

  // The calling thread leaves pipelines as `step` says.
  template <typename Step>
  void leave(Step step) {
    if (!tracedProc)
      return;
    std::uint64_t thread = llvm::get_threadid();
    std::lock_guard<std::mutex> lock(mutex);
    auto found = threads.find(thread);
    if (found == threads.end())
      return;
    step(found->second);
    if (found->second.depth != 0)
      return;
    if (found->second.profiler == idr::profile::Profiler::Begun)
      llvm::timeTraceProfilerFinishThread();
    threads.erase(found);
  }

  std::mutex mutex;
  llvm::DenseMap<std::uint64_t, Pipelines> threads;
};

// The zones of an LLVM pipeline's passes and analyses, registered once.
struct LlvmZones {
  llvm::PassInstrumentationCallbacks pic;

  LlvmZones() {
    pic.registerBeforeNonSkippedPassCallback(
        [](llvm::StringRef name, llvm::IRUnitRef ir) { beginLlvmZone(name, ir); });
    pic.registerAfterPassCallback(
        [](llvm::StringRef, llvm::IRUnitRef, const llvm::PreservedAnalyses &) { endZone(); });
    // The end of a pass whose IR unit it invalidated comes here instead.
    pic.registerAfterPassInvalidatedCallback(
        [](llvm::StringRef, const llvm::PreservedAnalyses &) { endZone(); });
    pic.registerBeforeAnalysisCallback(
        [](llvm::StringRef name, llvm::IRUnitRef ir) { beginLlvmZone(name, ir); });
    pic.registerAfterAnalysisCallback([](llvm::StringRef, llvm::IRUnitRef) { endZone(); });
  }
};

// Made with the process, so no first use races to register the callbacks;
// llvmCallbacks hands them out only while a trace runs.
LlvmZones llvmZones;

} // namespace

idr::profile::Trace::Trace(llvm::StringRef proc) {
  if (timeTraceFile.empty())
    return;
  tracedProc = proc.str();
  llvm::timeTraceProfilerInitialize(timeTraceGranularity, *tracedProc);
}

idr::profile::Trace::~Trace() {
  if (!tracedProc)
    return;
  if (llvm::Error error = llvm::timeTraceProfilerWrite(timeTraceFile, ""))
    llvm::errs() << *tracedProc << ": cannot write the time trace to " << timeTraceFile << ": "
                 << llvm::toString(std::move(error)) << "\n";
  llvm::timeTraceProfilerCleanup();
  tracedProc.reset();
}

idr::profile::ThreadTrace::ThreadTrace() {
  if (tracedProc && !llvm::getTimeTraceProfilerInstance()) {
    llvm::timeTraceProfilerInitialize(timeTraceGranularity, *tracedProc);
    profiler = Profiler::Begun;
  }
}

idr::profile::ThreadTrace::~ThreadTrace() {
  if (profiler == Profiler::Begun)
    llvm::timeTraceProfilerFinishThread();
}

void idr::profile::addInstrumentation(mlir::PassManager &pm) {
  pm.addInstrumentation(std::make_unique<Zones>());
}

llvm::PassInstrumentationCallbacks *idr::profile::llvmCallbacks() {
  if (!tracedProc)
    return nullptr;
  return &llvmZones.pic;
}
