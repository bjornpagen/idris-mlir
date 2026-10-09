// idr.canonicalize:counted: the rewrites of upstream's canonicalize,
// counted by the listener its configuration names. The counts by pattern
// are an Analysis remark, and a run that stops before its fixpoint (at
// max-iterations) is a Missed remark, both in the category
// idr-canonicalize.
export module idr.canonicalize:counted;

import idr.mlir;
import idr.support;

using namespace mlir;

export namespace idr::canonicalize {

// The listener of one canonicalizer. Upstream's pass keeps the listener
// its configuration names for as long as the pass lives, so this one
// starts the counts afresh for each run.
class Counter : public RewriterBase::Listener {
public:
  // Forgets the counts of the run before.
  void start() { run = std::make_unique<idr::support::PatternCounts>(); }

  void notifyPatternEnd(const Pattern &pattern, LogicalResult status) override {
    run->notifyPatternEnd(pattern, status);
  }

  // Reports the run on `op` as remarks, the counts and whether it stopped
  // before its fixpoint at that limit, and returns its rewrites.
  uint64_t report(Operation *op, LogicalResult converged, int64_t maxIterations) const {
    auto opts = remark::RemarkOpts::name("patterns").category("idr-canonicalize");
    if (auto symbol = op->getAttrOfType<StringAttr>(SymbolTable::getSymbolAttrName()))
      opts = opts.function(symbol.getValue());
    if (run->total() != 0)
      if (remark::detail::InFlightRemark out = remark::analysis(op->getLoc(), opts))
        run->addMetrics(out);
    if (succeeded(converged))
      return run->total();
    opts.remarkName = "unconverged";
    remark::missed(op->getLoc(), opts)
        << remark::reason("the greedy driver stopped before a fixpoint, at max-iterations={0}",
                          maxIterations);
    return run->total();
  }

private:
  std::unique_ptr<idr::support::PatternCounts> run;
};

} // namespace idr::canonicalize
