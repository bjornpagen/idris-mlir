// idr-canonicalize: upstream's canonicalize with its rewrites counted, as
// idr.canonicalize builds it.
//
// The totals are statistics. As for canonicalize, stopping early is no
// failure unless test-convergence asks for one.

#include "idr/Idr.h"

#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/Passes.h"

#include <memory>
#include <optional>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRCANONICALIZE
#include "idr/Passes.h.inc"
} // namespace idr

import idr.canonicalize;

namespace {

struct Canonicalize : idr::impl::IdrCanonicalizeBase<Canonicalize> {
  using IdrCanonicalizeBase::IdrCanonicalizeBase;
  Canonicalize() = default;

  // The pass manager copies a pass it has initialized to run it on several
  // operations at once, and gives the copy its options only after. The
  // copy builds a canonicalizer of its own from the options of the pass it
  // copies, which counts into the copy's listener. Those options built one
  // when that pass was initialized; a copy of a pass that was not is
  // initialized in turn, and reports there what fails here.
  Canonicalize(const Canonicalize &other) : IdrCanonicalizeBase(other) {
    (void)build(other, [](const Twine &) { return failure(); });
  }

  LogicalResult initialize(MLIRContext *context) override {
    return build(*this, [&](const Twine &message) -> LogicalResult {
      return emitError(UnknownLoc::get(context)) << "idr-canonicalize: " << message;
    });
  }

  // Upstream's canonicalize, configured as canonicalize configures itself
  // by default but for the iteration budget of `from`, reporting to this
  // pass's listener, as a pipeline of its own.
  LogicalResult build(const Canonicalize &from,
                      function_ref<LogicalResult(const Twine &)> error) {
    GreedyRewriteConfig config;
    config.setUseTopDownTraversal(true)
        .setRegionSimplificationLevel(GreedySimplifyRegionLevel::Normal)
        .setMaxIterations(from.maxIterations)
        .setListener(&counter);
    std::unique_ptr<Pass> pass = createCanonicalizerPass(config);
    // A run that stops before its fixpoint fails upstream's pass, which is
    // how it tells one; the configuration does not carry that.
    if (failed(pass->initializeOptions("test-convergence=true", error)))
      return failure();
    canonicalizer = OpPassManager();
    canonicalizer.addPass(std::move(pass));
    return success();
  }

  // Run nested under a symbol table whose symbols a parent pass holds as an
  // analysis (idr-inline does), the effects of a call, which the driver
  // asks of every call each time it simplifies the regions, look the
  // callee up there: the pass manager keeps a nested pass from adding or
  // erasing a symbol of its parent.
  void runOnOperation() override {
    Operation *op = getOperation();
    std::optional<idr::SymbolScope> scope;
    if (Operation *parent = op->getParentOp())
      if (Operation *table = SymbolTable::getNearestSymbolTable(parent))
        if (auto symbols = getCachedParentAnalysis<SymbolTable>(table))
          scope.emplace(table, symbols->get());
    counter.start();
    LogicalResult converged = runPipeline(canonicalizer, op);
    numRewrites += counter.report(op, converged, maxIterations);
    if (succeeded(converged))
      return;
    ++numUnconverged;
    if (testConvergence)
      signalPassFailure();
  }

  idr::canonicalize::Counter counter;
  OpPassManager canonicalizer;
};

} // namespace
