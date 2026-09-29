// idr-canonicalize: upstream's canonicalize (Canonicalizer.cpp), with its
// rewrites counted. It collects the same patterns (those of every loaded
// dialect and every registered op, as filter-dialects, disable-patterns and
// enable-patterns filter them), when canonicalize does (at initialization),
// and runs the same greedy driver with the same configuration, whose
// defaults are canonicalize's options, not GreedyRewriteConfig's. The only
// addition is a listener, which changes nothing the driver does: it counts
// the patterns that apply. So the IR is what canonicalize leaves.
//
// The totals are statistics. The counts by pattern are an Analysis remark,
// and a run that stops before its fixpoint (at max-iterations or
// max-num-rewrites) is a Missed remark, both in the category
// idr-canonicalize. As for canonicalize, stopping early is no failure unless
// test-convergence asks for one.

#include "Support/PatternCounts.h"
#include "idr/Idr.h"

#include "mlir/IR/Remarks.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/StringSwitch.h"

#include <memory>
#include <optional>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRCANONICALIZE
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

std::optional<GreedySimplifyRegionLevel> regionLevel(llvm::StringRef name) {
  return llvm::StringSwitch<std::optional<GreedySimplifyRegionLevel>>(name)
      .Case("disabled", GreedySimplifyRegionLevel::Disabled)
      .Case("normal", GreedySimplifyRegionLevel::Normal)
      .Case("aggressive", GreedySimplifyRegionLevel::Aggressive)
      .Default(std::nullopt);
}

struct Canonicalize : idr::impl::IdrCanonicalizeBase<Canonicalize> {
  using IdrCanonicalizeBase::IdrCanonicalizeBase;

  // The dialects filter-dialects names are loaded, as canonicalize loads them.
  void getDependentDialects(DialectRegistry &registry) const override {
    for (const std::string &name : filterDialects)
      registry.addDialectToPreload(StringRef(name));
  }

  LogicalResult initialize(MLIRContext *context) override {
    std::optional<GreedySimplifyRegionLevel> level = regionLevel(regionSimplifyLevel);
    if (!level)
      return emitError(UnknownLoc::get(context))
             << "idr-canonicalize: region-simplify is disabled, normal or aggressive, not "
             << regionSimplifyLevel;
    config.setUseTopDownTraversal(topDownProcessingEnabled);
    config.setRegionSimplificationLevel(*level);
    config.setMaxIterations(maxIterations);
    config.setMaxNumRewrites(maxNumRewrites);
    config.enableCSEBetweenIterations(cseBetweenIterations);

    llvm::DenseSet<TypeID> allowed;
    for (const std::string &name : filterDialects) {
      Dialect *dialect = context->getLoadedDialect(name);
      if (!dialect)
        return emitError(UnknownLoc::get(context))
               << "idr-canonicalize: filter-dialects names " << name << ", which is not loaded";
      allowed.insert(dialect->getTypeID());
    }
    auto isAllowed = [&](Dialect *dialect) {
      return allowed.empty() || allowed.contains(dialect->getTypeID());
    };
    RewritePatternSet owned(context);
    for (Dialect *dialect : context->getLoadedDialects())
      if (isAllowed(dialect))
        dialect->getCanonicalizationPatterns(owned);
    for (RegisteredOperationName op : context->getRegisteredOperations())
      if (isAllowed(&op.getDialect()))
        op.getCanonicalizationPatterns(owned, context);
    patterns = std::make_shared<FrozenRewritePatternSet>(std::move(owned), disabledPatterns,
                                                         enabledPatterns);
    return success();
  }

  void runOnOperation() override {
    Operation *op = getOperation();
    idr::support::PatternCounts counts;
    GreedyRewriteConfig counted = config;
    counted.setListener(&counts);
    LogicalResult converged = applyPatternsGreedily(op, *patterns, counted);
    numRewrites += counts.total();

    auto opts = remark::RemarkOpts::name("patterns").category("idr-canonicalize");
    if (auto symbol = op->getAttrOfType<StringAttr>(SymbolTable::getSymbolAttrName()))
      opts = opts.function(symbol.getValue());
    if (counts.total() != 0)
      if (remark::detail::InFlightRemark out = remark::analysis(op->getLoc(), opts))
        counts.addMetrics(out);
    if (succeeded(converged))
      return;
    ++numUnconverged;
    opts.remarkName = "unconverged";
    remark::missed(op->getLoc(), opts)
        << remark::reason("the greedy driver stopped before a fixpoint, at max-iterations={0} "
                          "or max-num-rewrites={1}",
                          config.getMaxIterations(), config.getMaxNumRewrites());
    if (testConvergence)
      signalPassFailure();
  }

  GreedyRewriteConfig config;
  std::shared_ptr<const FrozenRewritePatternSet> patterns;
};

} // namespace
