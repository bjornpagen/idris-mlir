// idr-simplify: the simplify loop. One
// round runs the passes of simplifyRound() in order; rounds repeat until one
// leaves the module unchanged, so running the loop again changes nothing.
// The loop ends because every member of a round is finite: loop breakers
// stop inlining at every cycle, specialization makes finitely many clones,
// and every evaluation removes a call. The round budget, `max-rounds`,
// asserts it: a module that still changes after that many rounds is the
// user error `unsupported (compile-time budget)`, not a hang.
//
// The loop is upstream's composite-fixed-point-pass over the round, told
// to stop silently when its budget runs out. It runs one round past the
// budget before it stops, and does not look at what that round changed: a
// module whose fixpoint takes at most `max-rounds` rounds passes, and one
// over the budget costs a round more, which is how this pass tells the two
// apart.
//
// PIN(simplify-structural-fixpoint) — see PINS.md
// "Unchanged" is OperationFingerPrint. sccp keeps the constants the module
// already holds, and remove-dead-values keeps a call it erases no result
// of, so a round at the fixpoint keeps the fingerprint.
//
// The round runs in a pipeline of the loop's, whose statistics the pass
// manager never prints: this pass shows them as its own. Two passes that
// change nothing open and close each round, so that this pass knows how
// many rounds ran and how long each took; the one that closes a round
// traces the module (functions, clones, ops) and the round's wall time in
// a remark. A loop that closed the round past the budget has spent it,
// which is the user error; a pass of that round that fails reports its own
// error instead, as it would in any round.

#include "idr/Idr.h"

#include "mlir/IR/Remarks.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/Passes.h"

#include "llvm/ADT/ScopeExit.h"

#include <algorithm>
#include <chrono>
#include <limits>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRSIMPLIFY
#include "idr/Passes.h.inc"
} // namespace idr

import idr.simplify;
import idr.support;

namespace {

// Where the loop is: the rounds that have closed, and when the last one
// opened.
struct Rounds {
  unsigned closed = 0;
  std::chrono::steady_clock::time_point opened;
};

// The first pass of each round.
struct OpenRound : PassWrapper<OpenRound, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(OpenRound)
  explicit OpenRound(Rounds &into) : rounds(into) {}
  StringRef getName() const final { return "IdrSimplifyOpenRound"; }
  void runOnOperation() override {
    rounds.opened = std::chrono::steady_clock::now();
    markAllAnalysesPreserved();
  }
  Rounds &rounds;
};

// The last pass of each round, which traces it.
struct CloseRound : PassWrapper<CloseRound, OperationPass<ModuleOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(CloseRound)
  explicit CloseRound(Rounds &into) : rounds(into) {}
  StringRef getName() const final { return "IdrSimplifyCloseRound"; }
  void runOnOperation() override {
    std::chrono::steady_clock::duration took = std::chrono::steady_clock::now() - rounds.opened;
    ++rounds.closed;
    idr::simplify::trace(getOperation(), rounds.closed, took);
    markAllAnalysesPreserved();
  }
  Rounds &rounds;
};

struct Simplify : idr::impl::IdrSimplifyBase<Simplify> {
  using IdrSimplifyBase::IdrSimplifyBase;
  Simplify() = default;

  // The pass manager copies a pass it has initialized to run it on several
  // modules at once, and gives the copy its options only after. The copy
  // builds a loop of its own from the options of the pass it copies, whose
  // rounds open and close in the copy, and declares its statistics before
  // it runs, as every instance does.
  Simplify(const Simplify &other) : IdrSimplifyBase(other) {
    (void)build(other.inlineIterations, other.maxRounds);
  }

  // The passes of one round, parsed from their textual pipelines.
  static LogicalResult buildRound(OpPassManager &pm, unsigned iterations) {
    for (const std::string &step : idr::simplify::simplifyRound(iterations))
      if (failed(parsePassPipeline(step, pm, llvm::errs())))
        return failure();
    return success();
  }

  // The loop: upstream's fixpoint of the round between the passes that open
  // and close it, which stops after the round past `budget`. The statistics
  // of the round's passes are this pass's.
  LogicalResult build(unsigned iterations, unsigned budget) {
    LogicalResult parsed = success();
    limit = std::min(budget, static_cast<unsigned>(std::numeric_limits<int>::max()));
    loop = OpPassManager(ModuleOp::getOperationName());
    loop.addPass(createCompositeFixedPointPass(
        "IdrSimplifyLoop",
        [&](OpPassManager &pm) {
          pm.addPass(std::make_unique<OpenRound>(rounds));
          parsed = buildRound(pm, iterations);
          pm.addPass(std::make_unique<CloseRound>(rounds));
          // The pipeline lives as long as the loop's pass, which owns it.
          statistics.declare(*this, pm);
        },
        static_cast<int>(limit), ConvergenceFailureAction::Silent));
    return parsed;
  }

  // Whether the loop ran out of its budget: upstream's pass stops right
  // after the round past it, and a loop that reaches its fixpoint closes at
  // most `limit` rounds.
  bool exhausted() const { return rounds.closed > limit; }

  LogicalResult initialize(MLIRContext *) override { return build(inlineIterations, maxRounds); }

  // The dialects a round's passes create must be loaded before any pass runs.
  void getDependentDialects(DialectRegistry &registry) const override {
    OpPassManager pm(ModuleOp::getOperationName());
    if (succeeded(buildRound(pm, inlineIterations)))
      pm.getDependentDialects(registry);
  }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    llvm::scope_exit finish([&] { report(module); });
    rounds = Rounds();
    // Upstream's pass takes a budget of one round at least; a budget of none
    // is spent before the first.
    if (limit != 0) {
      LogicalResult ran = runPipeline(loop, module);
      numRounds += rounds.closed;
      if (failed(ran))
        return signalPassFailure();
      if (!exhausted()) {
        remark::passed(module.getLoc(),
                       remark::RemarkOpts::name("idr-simplify").category("idr-simplify"))
            << remark::add("fixpoint: round {0} changed nothing", rounds.closed);
        return;
      }
    }
    emitError(module.getLoc()) << "unsupported (compile-time budget): idr-simplify did not "
                                  "reach a fixpoint in "
                               << static_cast<unsigned>(maxRounds) << " rounds";
    signalPassFailure();
  }

  // The round's statistics, as the loop's own and as a remark.
  void report(ModuleOp module) {
    statistics.fold();
    if (remark::detail::InFlightRemark out = remark::analysis(
            module.getLoc(), remark::RemarkOpts::name("statistics").category("idr-simplify")))
      statistics.addMetrics(out);
  }

  OpPassManager loop;
  // The rounds the loop may take, as many as upstream's pass can count.
  unsigned limit = 0;
  Rounds rounds;
  idr::support::PipelineStatistics statistics;
};

} // namespace
