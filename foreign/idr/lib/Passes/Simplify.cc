// idr-simplify: the simplify loop (OPT-PIPE-5, docs/cutover.md 6.3). One
// round runs the passes of simplifyRound() in order; rounds repeat until one
// leaves the module unchanged, so running the loop again changes nothing
// (OPT-IDEM-1). There is no bound on the number of rounds: the loop ends
// because loop breakers stop inlining at every cycle, clones are bounded by
// the clone limit, and every evaluation removes a call.
//
// "Unchanged" is structural(), not OperationFingerPrint. OperationFingerPrint
// hashes op pointers, and sccp replaces every constant value by a new
// constant op on every run (SCCP.cpp:54-60, replaceWithConstant), as
// remove-dead-values also rebuilds ops, so an unchanged module never has the
// same fingerprint twice. Nor is it the module's text: the constants that
// sccp and canonicalize materialize at the start of a block come out in
// another order on every round. structural() hashes what an op is, not where
// it lives: constants are hashed as their values at each use, and other
// values by their position in the walk.

#include "idr/Idr.h"
#include "idr/Passes.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/Remarks.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/SHA1.h"

#include <array>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRSIMPLIFY
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

struct Simplify : idr::impl::IdrSimplifyBase<Simplify> {
  using IdrSimplifyBase::IdrSimplifyBase;

  // The passes of one round, parsed from their textual pipelines.
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
    std::array<uint8_t, 20> before = structural(module);
    for (unsigned rounds = 1;; ++rounds) {
      if (failed(runPipeline(round, module)))
        return signalPassFailure();
      std::array<uint8_t, 20> after = structural(module);
      if (after == before) {
        remark::passed(module.getLoc(),
                       remark::RemarkOpts::name("idr-simplify").category("idr-simplify"))
            << remark::add("fixpoint: round {0} changed nothing", rounds);
        return;
      }
      before = after;
    }
  }

  // The hash of the module's ops, their attributes, properties and types,
  // their regions, and where each operand comes from. Attributes, types and
  // op names are uniqued, so their addresses stand for their contents.
  static std::array<uint8_t, 20> structural(ModuleOp module) {
    llvm::SHA1 hasher;
    auto add = [&](const void *data) {
      hasher.update(ArrayRef(reinterpret_cast<const uint8_t *>(&data), sizeof(data)));
    };
    auto addNumber = [&](uint64_t n) {
      hasher.update(ArrayRef(reinterpret_cast<const uint8_t *>(&n), sizeof(n)));
    };
    llvm::DenseMap<Value, uint64_t> numbers;
    auto number = [&](Value value) { numbers.try_emplace(value, numbers.size()); };
    module->walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (op->hasTrait<OpTrait::ConstantLike>())
        return;
      add(op->getName().getAsOpaquePointer());
      add(op->getRawDictionaryAttrs().getAsOpaquePointer());
      addNumber(op->hashProperties());
      for (Value operand : op->getOperands()) {
        Attribute constant;
        if (matchPattern(operand, m_Constant(&constant))) {
          add(constant.getAsOpaquePointer());
          add(operand.getType().getAsOpaquePointer());
        } else {
          addNumber(numbers.lookup(operand));
        }
      }
      for (Value result : op->getResults()) {
        number(result);
        add(result.getType().getAsOpaquePointer());
      }
      for (Region &region : op->getRegions()) {
        addNumber(region.getBlocks().size());
        for (Block &block : region)
          for (BlockArgument arg : block.getArguments()) {
            number(arg);
            add(arg.getType().getAsOpaquePointer());
          }
      }
    });
    return hasher.result();
  }

  OpPassManager round;
};

} // namespace

// OPT-PIPE-5: the passes of one round, as textual pipelines, in order.
//
// idr-prune runs right before remove-dead-values: at llvmorg-23.1.2,
// remove-dead-values erases the arguments of a function that dead-code
// analysis never reaches, while ops there still use them, and then folds
// those ops with a null operand (RemoveDeadValues.cpp, processFuncOp and the
// region-branch canonicalization at the end of runOnOperation). symbol-dce
// then removes the functions that only the emptied code referred to, which
// the analysis would find unreachable in turn.
SmallVector<std::string> idr::simplifyRound(unsigned inlineIterations, unsigned cloneLimit) {
  return {
      "idr-loop-breakers",
      "idr-effects",
      llvm::formatv("inline{{default-pipeline=canonicalize max-iterations={0}}", inlineIterations),
      llvm::formatv("idr-specialize{{clone-limit={0}}", cloneLimit),
      "sccp",
      "canonicalize",
      "cse",
      "idr-eval",
      "idr-prune",
      "symbol-dce",
      "remove-dead-values",
      "symbol-dce",
  };
}
