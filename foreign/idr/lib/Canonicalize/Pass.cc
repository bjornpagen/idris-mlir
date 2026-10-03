// idr-canonicalize: upstream's canonicalize with its rewrites counted, as
// idr.canonicalize runs it.
//
// The totals are statistics. As for canonicalize, stopping early is no
// failure unless test-convergence asks for one.

#include "idr/Idr.h"

#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

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

  // The dialects filter-dialects names are loaded, as canonicalize loads them.
  void getDependentDialects(DialectRegistry &registry) const override {
    for (const std::string &name : filterDialects)
      registry.addDialectToPreload(StringRef(name));
  }

  LogicalResult initialize(MLIRContext *context) override {
    std::optional<GreedySimplifyRegionLevel> level =
        idr::canonicalize::regionLevel(regionSimplifyLevel);
    if (!level)
      return emitError(UnknownLoc::get(context))
             << "idr-canonicalize: region-simplify is disabled, normal or aggressive, not "
             << regionSimplifyLevel;
    config.setUseTopDownTraversal(topDownProcessingEnabled);
    config.setRegionSimplificationLevel(*level);
    config.setMaxIterations(maxIterations);
    config.setMaxNumRewrites(maxNumRewrites);
    config.enableCSEBetweenIterations(cseBetweenIterations);

    FailureOr<std::shared_ptr<const FrozenRewritePatternSet>> collected =
        idr::canonicalize::collect(context, filterDialects, disabledPatterns, enabledPatterns);
    if (failed(collected))
      return failure();
    patterns = std::move(*collected);
    return success();
  }

  void runOnOperation() override {
    idr::canonicalize::Counted counted =
        idr::canonicalize::applyCounted(getOperation(), *patterns, config);
    numRewrites += counted.rewrites;
    if (succeeded(counted.converged))
      return;
    ++numUnconverged;
    if (testConvergence)
      signalPassFailure();
  }

  GreedyRewriteConfig config;
  std::shared_ptr<const FrozenRewritePatternSet> patterns;
};

} // namespace
