// idr-simplify: the simplify loop. One round runs the passes
// buildSimplifyRound adds, in order; rounds repeat until one leaves the
// module unchanged, so running the loop again changes nothing. The loop
// ends because every member of a round is finite: loop breakers stop
// inlining at every cycle, and specialization makes finitely many clones.
// The round budget, `max-rounds`, asserts it: a module that still changes
// after that many rounds is the user error `unsupported (compile-time
// budget)`, not a hang.
//
// The loop is upstream's composite-fixed-point-pass over the round, told
// to stop silently when its budget runs out. It runs one round past the
// budget before it stops, and does not look at what that round changed: a
// module whose fixpoint takes at most `max-rounds` rounds passes, and one
// over the budget costs a round more, which is how this pass tells the two
// apart.
//
// PIN(simplify-structural-fixpoint) — see PINS.md
// "Unchanged" is the composite's structural fingerprint of the module,
// taken once per round. sccp keeps the constants the module already
// holds, and remove-dead-values keeps a call it erases no result of, so a
// round at the fixpoint keeps the fingerprint.
//
// A pass sees no instrumentation, and the round runs in the composite's
// pipeline, whose statistics the pass manager never prints. So the loop's
// instrumentation, which the manager's owner adds, counts the rounds: it
// finds the round's pipelines by the composite that runs them, which is
// the one pass of this pass's loop. It times and traces each round,
// reports the statistics of the round's passes, and hands this pass the
// count; the instrumentation observes, and this pass judges.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Simplify.h"
#include "idr/Support/Profile.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Remarks.h"
#include "mlir/Pass/PassInstrumentation.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Passes.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Support/FormatVariadic.h"

#include <algorithm>
#include <chrono>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>

namespace idr {
#define GEN_PASS_DEF_IDRSIMPLIFY
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

// A pass statistic must have the layout the MLIR library gives it, which
// holds the count: the pinned LLVM is built with LLVM_FORCE_ENABLE_STATS,
// so its llvm-config.h says statistics count in our Release build too.
static_assert(LLVM_ENABLE_STATS, "pass statistics need an LLVM built with LLVM_FORCE_ENABLE_STATS");

namespace {

using Clock = std::chrono::steady_clock;

// One run of idr-simplify, as its instrumentation sees it.
struct Rounds {
  Operation *module = nullptr;
  // The pass that runs each round's pipeline.
  Pass *composite = nullptr;
  unsigned closed = 0;
  Clock::time_point opened;
  // The statistics of the round's passes, summed by `<pass>.<statistic>`;
  // ordered, so that what reports them does not depend on thread timing.
  std::map<std::string, uint64_t> totals;
  // The values of each running pass's statistics when it began.
  llvm::DenseMap<Pass *, SmallVector<uint64_t, 4>> inFlight;
};

struct Simplify : idr::impl::IdrSimplifyBase<Simplify> {
  using IdrSimplifyBase::IdrSimplifyBase;
  Simplify() = default;

  // The pass manager copies a pass it has initialized, to run it on several
  // modules at once. The copy runs a copy of the loop (the composite copies
  // its round) and is handed a record of its own when it runs.
  Simplify(const Simplify &other) : IdrSimplifyBase(other), loop(other.loop), limit(other.limit) {}

  LogicalResult initialize(MLIRContext *) override {
    limit = std::min(static_cast<unsigned>(maxRounds),
                     static_cast<unsigned>(std::numeric_limits<int>::max()));
    loop = OpPassManager(ModuleOp::getOperationName());
    loop.addPass(createCompositeFixedPointPass("IdrSimplifyRound", idr::buildSimplifyRound,
                                               static_cast<int>(limit),
                                               ConvergenceFailureAction::Silent));
    return success();
  }

  // The dialects a round's passes create must be loaded before any pass runs.
  void getDependentDialects(DialectRegistry &registry) const override {
    OpPassManager round(ModuleOp::getOperationName());
    idr::buildSimplifyRound(round);
    round.getDependentDialects(registry);
  }

  Pass *composite() { return &*loop.getPasses().begin(); }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    if (!rounds) {
      emitError(module.getLoc()) << "internal error: idr-simplify runs only under a pass manager "
                                    "that registered its instrumentation";
      return signalPassFailure();
    }
    // Upstream's pass takes a budget of one round at least; a budget of none
    // is spent before the first.
    if (limit != 0) {
      LogicalResult ran = runPipeline(loop, module);
      numRounds += rounds->closed;
      // The pass that failed reported why; the budget did not run out.
      if (failed(ran))
        return signalPassFailure();
      // A loop that reaches its fixpoint closes at most `limit` rounds.
      if (rounds->closed <= limit)
        return;
    }
    emitError(module.getLoc()) << "unsupported (compile-time budget): idr-simplify did not "
                                  "reach a fixpoint in "
                               << static_cast<unsigned>(maxRounds) << " rounds";
    signalPassFailure();
  }

  OpPassManager loop;
  // The rounds the loop may take, as many as upstream's pass can count.
  unsigned limit = 0;
  // This run's record, which the instrumentation opens before the run and
  // closes after it.
  Rounds *rounds = nullptr;
};

// What the module holds after a round.
struct Census {
  unsigned functions = 0, clones = 0;
  uint64_t ops = 0;
};

Census takeCensus(ModuleOp module) {
  Census census;
  for (idr::FuncOp fn : module.getOps<idr::FuncOp>()) {
    ++census.functions;
    if (fn.getClone())
      ++census.clones;
  }
  module.walk([&](Operation *) { ++census.ops; });
  return census;
}

// The remark after round `round`: what the module holds, and how long the
// round took.
void traceRound(ModuleOp module, unsigned round, Clock::duration took,
                llvm::function_ref<const Census &()> census) {
  remark::detail::InFlightRemark out = remark::analysis(
      module.getLoc(), remark::RemarkOpts::name("round").category("idr-simplify"));
  // The census walks the module: only for a remark someone reads.
  if (!out)
    return;
  const Census &counts = census();
  double ms = std::chrono::duration<double, std::milli>(took).count();
  out << remark::metric("round", round) << remark::metric("functions", counts.functions)
      << remark::metric("clones", counts.clones) << remark::metric("ops", counts.ops)
      << remark::metric("ms", llvm::formatv("{0:f3}", ms).str());
}

// The statistics of the round's passes, which -mlir-pass-statistics never
// prints: the passes run in the composite's pipeline, not the manager's.
void reportStatistics(ModuleOp module, const std::map<std::string, uint64_t> &totals) {
  if (remark::detail::InFlightRemark out = remark::analysis(
          module.getLoc(), remark::RemarkOpts::name("statistics").category("idr-simplify")))
    for (const auto &[name, total] : totals)
      out << remark::metric(name, total);
}

SmallVector<uint64_t, 4> valuesOf(Pass *pass) {
  SmallVector<uint64_t, 4> values;
  for (const Pass::Statistic *statistic : pass->getStatistics())
    values.push_back(statistic->getValue());
  return values;
}

// Whether the instrumentation sums `pass`'s statistics: a pass that has
// some, is no adaptor, and is not the loop. The test reads only the pass,
// so a pass without statistics never takes the lock.
bool counted(Pass *pass) {
  return !pass->getStatistics().empty() && !pass->getArgument().empty() && !isa<Simplify>(pass);
}

// The composite's own argument, which every composite has. The pipelines
// a nest or the inliner runs, one per function, have another parent, and
// this test, which reads only that parent, keeps them from the lock.
constexpr llvm::StringLiteral compositeArgument = "composite-fixed-point-pass";

class SimplifyInstrumentation : public PassInstrumentation {
public:
  void runBeforePass(Pass *pass, Operation *op) override {
    if (auto *simplify = dyn_cast<Simplify>(pass)) {
      auto record = std::make_unique<Rounds>();
      record->module = op;
      record->composite = simplify->composite();
      simplify->rounds = record.get();
      std::lock_guard<std::mutex> lock(mutex);
      records[simplify] = std::move(record);
      return;
    }
    if (!counted(pass))
      return;
    SmallVector<uint64_t, 4> values = valuesOf(pass);
    std::lock_guard<std::mutex> lock(mutex);
    if (Rounds *record = enclosing(op))
      record->inFlight[pass] = std::move(values);
  }

  void runAfterPass(Pass *pass, Operation *) override {
    if (auto *simplify = dyn_cast<Simplify>(pass))
      return finish(simplify, /*passed=*/true);
    if (!counted(pass))
      return;
    SmallVector<uint64_t, 4> values = valuesOf(pass);
    std::lock_guard<std::mutex> lock(mutex);
    for (auto &entry : records) {
      Rounds &record = *entry.second;
      auto found = record.inFlight.find(pass);
      if (found == record.inFlight.end())
        continue;
      // Deltas, since a statistic sums over its pass instance, and the
      // nests keep one instance per thread across rounds.
      for (auto [statistic, before, now] :
           llvm::zip_equal(pass->getStatistics(), found->second, values))
        record.totals[(pass->getArgument() + "." + statistic->getName()).str()] += now - before;
      record.inFlight.erase(found);
      return;
    }
  }

  void runAfterPassFailed(Pass *pass, Operation *) override {
    if (auto *simplify = dyn_cast<Simplify>(pass))
      return finish(simplify, /*passed=*/false);
    if (!counted(pass))
      return;
    std::lock_guard<std::mutex> lock(mutex);
    for (auto &entry : records)
      entry.second->inFlight.erase(pass);
  }

  // A pipeline's parent is the pass whose runPipeline runs it (the
  // adaptor builds its PipelineParentInfo from that pass), so a round's
  // pipeline is the one whose parent is a record's composite.
  void runBeforePipeline(std::optional<OperationName>, const PipelineParentInfo &info) override {
    if (info.parentPass->getArgument() != compositeArgument)
      return;
    std::lock_guard<std::mutex> lock(mutex);
    if (Rounds *record = roundOf(info.parentPass))
      record->opened = Clock::now();
  }

  void runAfterPipeline(std::optional<OperationName>, const PipelineParentInfo &info) override {
    if (info.parentPass->getArgument() != compositeArgument)
      return;
    Operation *module = nullptr;
    unsigned round = 0;
    Clock::duration took{};
    {
      std::lock_guard<std::mutex> lock(mutex);
      Rounds *record = roundOf(info.parentPass);
      if (!record)
        return;
      round = ++record->closed;
      took = Clock::now() - record->opened;
      module = record->module;
    }
    // On the pass thread, after the round: the census sees the module as
    // the round left it, and is taken at most once.
    std::optional<Census> counts;
    auto census = [&]() -> const Census & {
      if (!counts)
        counts = takeCensus(cast<ModuleOp>(module));
      return *counts;
    };
    traceRound(cast<ModuleOp>(module), round, took, census);
    IDR_INSTANT("round");
  }

private:
  // The record of the run `op` is in. Under the lock.
  Rounds *enclosing(Operation *op) {
    for (auto &entry : records)
      if (entry.second->module == op || entry.second->module->isProperAncestor(op))
        return entry.second.get();
    return nullptr;
  }

  // The record whose composite is `pass`. Under the lock.
  Rounds *roundOf(Pass *pass) {
    for (auto &entry : records)
      if (entry.second->composite == pass)
        return entry.second.get();
    return nullptr;
  }

  // The run of `simplify` ended: the fixpoint remark when it reached one,
  // then the statistics, and the record closes.
  void finish(Simplify *simplify, bool passed) {
    std::unique_ptr<Rounds> record;
    {
      std::lock_guard<std::mutex> lock(mutex);
      auto found = records.find(simplify);
      if (found == records.end())
        return;
      record = std::move(found->second);
      records.erase(found);
    }
    simplify->rounds = nullptr;
    auto module = cast<ModuleOp>(record->module);
    if (passed && record->closed <= simplify->limit)
      remark::passed(module.getLoc(),
                     remark::RemarkOpts::name("idr-simplify").category("idr-simplify"))
          << remark::add("fixpoint: round {0} changed nothing", record->closed);
    reportStatistics(module, record->totals);
  }

  // The nests' hooks arrive from worker threads.
  std::mutex mutex;
  // One record per running idr-simplify, each where its pass points: a
  // record does not move when another is opened.
  llvm::DenseMap<Simplify *, std::unique_ptr<Rounds>> records;
};

} // namespace

std::unique_ptr<PassInstrumentation> idr::createSimplifyInstrumentation() {
  return std::make_unique<SimplifyInstrumentation>();
}
