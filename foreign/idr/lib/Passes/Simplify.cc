// idr-simplify: the simplify loop. One
// round runs the passes of simplifyRound() in order; rounds repeat until one
// leaves the module unchanged, so running the loop again changes nothing.
// The loop ends because every member of a round is finite: loop breakers
// stop inlining at every cycle, specialization makes finitely many clones,
// and every evaluation removes a call. The round budget, `max-rounds`,
// asserts it: a module that still changes after that many rounds is the
// user error `unsupported (compile-time budget)`, not a hang.
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
//
// The round's passes run in the loop's own pipeline, whose statistics the
// pass manager never prints: the loop shows them as its own. After each
// round a remark traces the module (functions, clones, ops) and the round's
// wall time.

#include "Support/PipelineStatistics.h"
#include "idr/Idr.h"
#include "idr/Passes.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/Remarks.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

#include "llvm/ADT/ScopeExit.h"
#include "llvm/Support/FormatVariadic.h"
#include "llvm/Support/SHA1.h"

#include <array>
#include <chrono>
#include <limits>

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
    std::array<uint8_t, 20> before = structural(module);
    unsigned budget = maxRounds;
    for (unsigned rounds = 1; rounds <= budget; ++rounds) {
      auto started = std::chrono::steady_clock::now();
      if (failed(runPipeline(round, module)))
        return signalPassFailure();
      ++numRounds;
      trace(module, rounds, std::chrono::steady_clock::now() - started);
      std::array<uint8_t, 20> after = structural(module);
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

  // The remark after round `n`: what the module holds, and how long the
  // round took.
  static void trace(ModuleOp module, unsigned n, std::chrono::steady_clock::duration took) {
    remark::detail::InFlightRemark out = remark::analysis(
        module.getLoc(), remark::RemarkOpts::name("round").category("idr-simplify"));
    // The walk costs as much as the module is large: only for a remark
    // someone reads.
    if (!out)
      return;
    unsigned functions = 0, clones = 0;
    for (auto fn : module.getOps<func::FuncOp>()) {
      ++functions;
      if (fn->hasAttr("idr.origin"))
        ++clones;
    }
    uint64_t ops = 0;
    module.walk([&](Operation *) { ++ops; });
    double ms = std::chrono::duration<double, std::milli>(took).count();
    out << remark::metric("round", n) << remark::metric("functions", functions)
        << remark::metric("clones", clones) << remark::metric("ops", ops)
        << remark::metric("ms", llvm::formatv("{0:f3}", ms).str());
  }

  // The round's statistics, as the loop's own and as a remark.
  void report(ModuleOp module) {
    statistics.fold();
    if (remark::detail::InFlightRemark out = remark::analysis(
            module.getLoc(), remark::RemarkOpts::name("statistics").category("idr-simplify")))
      statistics.addMetrics(out);
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
  idr::support::PipelineStatistics statistics;
};

} // namespace

// The passes of one round, as textual pipelines, in order.
//
// The inliner simplifies each function and inlines the calls that exposes
// until an iteration inlines nothing, not a fixed number of times (upstream's
// default is 4): unfolding a sequence of n actions, as a `do` block of n
// statements is (each `>>` applies the closure of the rest), takes n
// iterations, each of which canonicalizes the function, while each round
// runs every pass on the whole module; with a bound, the loop took a round
// for every statement or two, each as long as the program is large. The
// iterations end as the rounds do: every cycle of references keeps a loop
// breaker, and inlining and canonicalization only copy references that
// exist, so no iteration closes a new cycle.
//
// idr-prune runs right before remove-dead-values: at llvmorg-23.1.2,
// remove-dead-values erases the arguments of a function that dead-code
// analysis never reaches, while ops there still use them, and then folds
// those ops with a null operand (RemoveDeadValues.cpp, processFuncOp and the
// region-branch canonicalization at the end of runOnOperation). symbol-dce
// then removes the functions that only the emptied code referred to, which
// the analysis would find unreachable in turn.
//
// Specialization has no limit to pass: it is finite by construction, and its
// budget is an assertion of its own.
SmallVector<std::string> idr::simplifyRound(unsigned inlineIterations, unsigned) {
  return {
      "idr-loop-breakers",
      "idr-effects",
      llvm::formatv("idr-inline{{default-pipeline=idr-canonicalize max-iterations={0}}",
                    inlineIterations),
      "idr-specialize",
      "sccp",
      "idr-canonicalize",
      "cse",
      "idr-eval",
      "idr-prune",
      "symbol-dce",
      "remove-dead-values",
      "symbol-dce",
  };
}
