// idr.canonicalize:counted: canonicalize's greedy driver, with its
// rewrites counted. The counts by pattern are an Analysis remark, and a
// run that stops before its fixpoint (at max-iterations or
// max-num-rewrites) is a Missed remark, both in the category
// idr-canonicalize.
export module idr.canonicalize:counted;

import idr.mlir;
import idr.support;

using namespace mlir;

export namespace idr::canonicalize {

// What a run did: the rewrites of every pattern, and whether the driver
// reached its fixpoint.
struct Counted {
  uint64_t rewrites;
  llvm::LogicalResult converged;
};

// Applies `patterns` to `op` as `config` says, counting the patterns that
// apply, and reports the counts and an early stop as remarks.
Counted applyCounted(Operation *op, const FrozenRewritePatternSet &patterns,
                     const GreedyRewriteConfig &config) {
  idr::support::PatternCounts counts;
  GreedyRewriteConfig counted = config;
  counted.setListener(&counts);
  LogicalResult converged = applyPatternsGreedily(op, patterns, counted);

  auto opts = remark::RemarkOpts::name("patterns").category("idr-canonicalize");
  if (auto symbol = op->getAttrOfType<StringAttr>(SymbolTable::getSymbolAttrName()))
    opts = opts.function(symbol.getValue());
  if (counts.total() != 0)
    if (remark::detail::InFlightRemark out = remark::analysis(op->getLoc(), opts))
      counts.addMetrics(out);
  if (succeeded(converged))
    return {counts.total(), converged};
  opts.remarkName = "unconverged";
  remark::missed(op->getLoc(), opts)
      << remark::reason("the greedy driver stopped before a fixpoint, at max-iterations={0} "
                        "or max-num-rewrites={1}",
                        config.getMaxIterations(), config.getMaxNumRewrites());
  return {counts.total(), converged};
}

} // namespace idr::canonicalize
