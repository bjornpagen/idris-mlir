// idr-simplify: the simplify loop. One
// round runs the passes of simplifyRound() in order; rounds repeat until one
// leaves the module unchanged, so running the loop again changes nothing.
// The loop ends because every member of a round is finite: loop breakers
// stop inlining at every cycle, specialization makes finitely many clones,
// and every evaluation removes a call. The round budget, `max-rounds`,
// asserts it: a module that still changes after that many rounds is the
// user error `unsupported (compile-time budget)`, not a hang.
//
// PIN(simplify-structural-fixpoint) — see PINS.md
// "Unchanged" is OperationFingerPrint. sccp keeps the constants the module
// already holds, and idr-dead-values leaves a call remove-dead-values would
// rebuild without changing, so a round at the fixpoint keeps the
// fingerprint. The loop is still ours: composite-fixed-point-pass warns and
// goes on when the budget runs out, and the round's statistics and remarks
// are the loop's.
//
// The round's passes run in the loop's own pipeline, whose statistics the
// pass manager never prints: the loop shows them as its own. After each
// round a remark traces the module (functions, clones, ops) and the round's
// wall time.

#include "idr/Idr.h"

#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/Remarks.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

#include "llvm/ADT/ScopeExit.h"

#include <array>
#include <chrono>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRSIMPLIFY
#include "idr/Passes.h.inc"
} // namespace idr

import idr.simplify;
import idr.support;

namespace {

struct Simplify : idr::impl::IdrSimplifyBase<Simplify> {
  using IdrSimplifyBase::IdrSimplifyBase;

  // The passes of one round, parsed from their textual pipelines.
  LogicalResult buildRound(OpPassManager &pm) const {
    for (const std::string &step : idr::simplify::simplifyRound(inlineIterations))
      if (failed(parsePassPipeline(step, pm, llvm::errs())))
        return failure();
    return success();
  }

  LogicalResult initialize(MLIRContext *) override {
    round = OpPassManager(ModuleOp::getOperationName());
    if (failed(buildRound(round)))
      return failure();
    statistics.declare(*this, round);
    return success();
  }

  // The dialects a round's passes create must be loaded before any pass runs.
  void getDependentDialects(DialectRegistry &registry) const override {
    OpPassManager pm(ModuleOp::getOperationName());
    if (succeeded(buildRound(pm)))
      pm.getDependentDialects(registry);
  }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    llvm::scope_exit finish([&] { report(module); });
    OperationFingerPrint before(module);
    unsigned budget = maxRounds;
    for (unsigned rounds = 1; rounds <= budget; ++rounds) {
      auto started = std::chrono::steady_clock::now();
      if (failed(runPipeline(round, module)))
        return signalPassFailure();
      ++numRounds;
      idr::simplify::trace(module, rounds, std::chrono::steady_clock::now() - started);
      OperationFingerPrint after(module);
      if (after == before) {
        remark::passed(module.getLoc(),
                       remark::RemarkOpts::name("idr-simplify").category("idr-simplify"))
            << remark::add("fixpoint: round {0} changed nothing", rounds);
        return;
      }
      before = after;
    }
    emitError(module.getLoc()) << "unsupported (compile-time budget): idr-simplify did not "
                                  "reach a fixpoint in "
                               << budget << " rounds";
    signalPassFailure();
  }

  // The round's statistics, as the loop's own and as a remark.
  void report(ModuleOp module) {
    statistics.fold();
    if (remark::detail::InFlightRemark out = remark::analysis(
            module.getLoc(), remark::RemarkOpts::name("statistics").category("idr-simplify")))
      statistics.addMetrics(out);
  }

  OpPassManager round;
  idr::support::PipelineStatistics statistics;
};

} // namespace
