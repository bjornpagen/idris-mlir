// idr-simplify: the simplify loop (OPT-PIPE-5, docs/cutover.md 6.3). One
// round runs the passes of simplifyRound() in order; rounds repeat until one
// leaves the module unchanged, so running the loop again changes nothing
// (OPT-IDEM-1). There is no bound on the number of rounds: the loop ends
// because loop breakers stop inlining at every cycle, clones are bounded by
// the clone limit, and every evaluation removes a call.
//
// "Unchanged" is the module's text, not OperationFingerPrint: that hashes
// op pointers, and sccp replaces every constant value by a new constant op
// on every run (SCCP.cpp:54-60, replaceWithConstant), as remove-dead-values
// also rebuilds ops, so the fingerprint of an unchanged module changes on
// every round and the loop would never end.

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
  // live in other parts of the library. Returns the steps left out.
  FailureOr<SmallVector<std::string>> buildRound(OpPassManager &pm) const {
    SmallVector<std::string> skipped;
    for (const std::string &step : idr::simplifyRound(inlineIterations, cloneLimit)) {
      StringRef name = StringRef(step).take_until([](char c) { return c == '{'; });
      if (skipUnregistered && !PassInfo::lookup(name)) {
        skipped.push_back(name.str());
        continue;
      }
      if (failed(parsePassPipeline(step, pm, llvm::errs())))
        return failure();
    }
    return skipped;
  }

  LogicalResult initialize(MLIRContext *) override {
    round = OpPassManager(ModuleOp::getOperationName());
    FailureOr<SmallVector<std::string>> left = buildRound(round);
    if (failed(left))
      return failure();
    skipped = std::move(*left);
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
    for (const std::string &name : skipped)
      module.emitWarning("idr-simplify: the round leaves out ")
          << name << ", which is not registered (skip-unregistered)";
    std::string before = text(module);
    while (true) {
      if (failed(runPipeline(round, module)))
        return signalPassFailure();
      std::string after = text(module);
      if (after == before)
        return;
      before = std::move(after);
    }
  }

  static std::string text(ModuleOp module) {
    std::string out;
    llvm::raw_string_ostream os(out);
    module->print(os, OpPrintingFlags().assumeVerified());
    return out;
  }

  OpPassManager round;
  SmallVector<std::string> skipped;
};

} // namespace

// OPT-PIPE-5: the passes of one round, as textual pipelines, in order.
//
// symbol-dce also runs before remove-dead-values: at llvmorg-23.1.2,
// remove-dead-values on a private function that nothing calls but itself
// erases the arguments that a region op kept for its effects still uses, and
// then folds that op with a null operand (RemoveDeadValues.cpp, processFuncOp
// and the region-branch canonicalization at the end of runOnOperation).
SmallVector<std::string> idr::simplifyRound(unsigned inlineIterations, unsigned cloneLimit) {
  return {
      "idr-effects",
      llvm::formatv("inline{{default-pipeline=canonicalize max-iterations={0}}", inlineIterations),
      llvm::formatv("idr-specialize{{clone-limit={0}}", cloneLimit),
      "sccp",
      "canonicalize",
      "cse",
      "idr-eval",
      "symbol-dce",
      "remove-dead-values",
      "symbol-dce",
  };
}
