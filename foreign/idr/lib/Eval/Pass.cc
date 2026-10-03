// idr-eval: the pass, whose cache of outcomes lasts the compilation, over
// idr.eval.

#include "idr/Idr.h"

namespace idr {
#define GEN_PASS_DEF_IDREVAL
#include "idr/Passes.h.inc"
} // namespace idr

import idr.mlir;
import idr.eval;

using namespace mlir;

namespace {

struct Eval : idr::impl::IdrEvalBase<Eval> {
  void runOnOperation() override {
    idr::eval::Statistics stats;
    LogicalResult result = idr::eval::evaluate(
        getOperation(), cache, stats,
        [&](OpPassManager &pipeline, Operation *op) { return runPipeline(pipeline, op); });
    numEvaluated += stats.evaluated;
    numStayedCrash += stats.stayedCrash;
    numStayedBudget += stats.stayedBudget;
    numStayedLarge += stats.stayedLarge;
    numCacheHits += stats.cacheHits;
    if (failed(result))
      signalPassFailure();
  }

  // The dialects the round's lowering creates, and the translation to LLVM
  // IR, are loaded before any pass runs.
  void getDependentDialects(DialectRegistry &registry) const override {
    IdrEvalBase::getDependentDialects(registry);
    registerBuiltinDialectTranslation(registry);
    registerLLVMDialectTranslation(registry);
  }

private:
  // Results for the compilation, which the simplify loop runs round after
  // round with this pass. A call that stays is known too, so it is not run
  // again.
  idr::eval::Cache cache;
};

} // namespace
