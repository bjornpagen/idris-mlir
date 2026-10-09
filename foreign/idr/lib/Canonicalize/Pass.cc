// idr-canonicalize: upstream's canonicalize with its rewrites counted, as
// idr.canonicalize builds it.
//
// The totals are statistics. As for canonicalize, stopping early is no
// failure unless test-convergence asks for one.

#include "idr/Idr.h"

#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/Passes.h"

#include "llvm/ADT/StringExtras.h"

#include <memory>
#include <optional>
#include <string>

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

  // The dialects filter-dialects names are loaded, as canonicalize loads
  // them: the pass manager loads none for a pipeline a pass runs.
  void getDependentDialects(DialectRegistry &registry) const override {
    for (const std::string &name : filterDialects)
      registry.addDialectToPreload(StringRef(name));
  }

  LogicalResult initialize(MLIRContext *context) override {
    return build(*this, [&](const Twine &message) -> LogicalResult {
      return emitError(UnknownLoc::get(context)) << "idr-canonicalize: " << message;
    });
  }

  // Upstream's canonicalize, configured by the options of `from`, reporting
  // to this pass's listener, as a pipeline of its own.
  LogicalResult build(const Canonicalize &from,
                      function_ref<LogicalResult(const Twine &)> error) {
    std::optional<GreedySimplifyRegionLevel> level =
        idr::canonicalize::regionLevel(from.regionSimplifyLevel);
    if (!level)
      return error("region-simplify is disabled, normal or aggressive, not " +
                   StringRef(from.regionSimplifyLevel));
    GreedyRewriteConfig config;
    config.setUseTopDownTraversal(from.topDownProcessingEnabled)
        .setRegionSimplificationLevel(*level)
        .setMaxIterations(from.maxIterations)
        .setMaxNumRewrites(from.maxNumRewrites)
        .enableCSEBetweenIterations(from.cseBetweenIterations)
        .setListener(&counter);
    std::unique_ptr<Pass> pass =
        createCanonicalizerPass(config, from.disabledPatterns, from.enabledPatterns);
    // What the configuration does not carry: the dialects whose patterns
    // are collected, and a failure for a run that stops before its
    // fixpoint, which is how upstream's pass tells one.
    std::string rest = "test-convergence=true";
    if (!from.filterDialects.empty())
      rest += " filter-dialects=" + llvm::join(from.filterDialects, ",");
    if (failed(pass->initializeOptions(rest, error)))
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
    numRewrites += counter.report(op, converged, maxIterations, maxNumRewrites);
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
