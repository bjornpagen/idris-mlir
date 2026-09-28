// idr-simplify: the simplify loop (OPT-PIPE-5, docs/cutover.md 6.3). One
// round runs the passes of simplifyRound() in order; rounds repeat until one
// leaves the module's fingerprint unchanged, so running the loop again
// changes nothing (OPT-IDEM-1). There is no bound on the number of rounds:
// the loop ends because loop breakers stop inlining at every cycle, clones
// are bounded by the clone limit, and every evaluation removes a call.

#include "idr/Idr.h"
#include "idr/Passes.h"

#include "mlir/IR/OperationSupport.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

#include "llvm/Support/FormatVariadic.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRSIMPLIFY
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

struct Simplify : idr::impl::IdrSimplifyBase<Simplify> {
  using IdrSimplifyBase::IdrSimplifyBase;

  // The passes of a round are named, not linked: idr-effects and idr-eval
  // live in other parts of the library.
  LogicalResult buildRound(OpPassManager &pm) const {
    for (const std::string &step : idr::simplifyRound(inlineIterations, cloneLimit))
      if (failed(parsePassPipeline(step, pm, llvm::errs())))
        return failure();
    return success();
  }

  LogicalResult initialize(MLIRContext *) override {
    round = OpPassManager(ModuleOp::getOperationName());
    return buildRound(round);
  }

  // The dialects a round's passes create must be loaded before any pass runs.
  void getDependentDialects(DialectRegistry &registry) const override {
    OpPassManager pm(ModuleOp::getOperationName());
    if (succeeded(buildRound(pm)))
      pm.getDependentDialects(registry);
  }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    OperationFingerPrint before(module);
    while (true) {
      if (failed(runPipeline(round, module)))
        return signalPassFailure();
      OperationFingerPrint after(module);
      if (after == before)
        return;
      before = after;
    }
  }

  OpPassManager round;
};

} // namespace

// OPT-PIPE-5: the passes of one round, as textual pipelines, in order.
SmallVector<std::string> idr::simplifyRound(unsigned inlineIterations, unsigned cloneLimit) {
  return {
      "idr-effects",
      llvm::formatv("inline{{default-pipeline=canonicalize max-iterations={0}}", inlineIterations),
      llvm::formatv("idr-specialize{{clone-limit={0}}", cloneLimit),
      "sccp",
      "canonicalize",
      "cse",
      "idr-eval",
      "remove-dead-values",
      "symbol-dce",
  };
}
