// idr.canonicalize:counted: the rewrites of one canonicalize, counted by
// the listener its configuration names. The counts by pattern are an
// Analysis remark, and a run that stops before its fixpoint (at
// max-iterations) is a Missed remark, both in the category
// idr-canonicalize.
export module idr.canonicalize:counted;

import idr.mlir;
import idr.support;

using namespace mlir;

export namespace idr::canonicalize {

// The listener of one run of the greedy driver. The pass builds it in
// runOnOperation, beside the configuration and the change flag, and drops
// it when that run returns. A fold, and a constant uniqued while the
// worklist is built, are rewrites and not patterns. The driver reports
// them here, and the pass verifies them.
class Counter : public RewriterBase::Listener {
public:
  void notifyPatternEnd(const Pattern &pattern, LogicalResult status) override {
    run.notifyPatternEnd(pattern, status);
  }

  void notifyOperationInserted(Operation *, OpBuilder::InsertPoint) override {
    rewritten = true;
  }
  void notifyBlockInserted(Block *, Region *, Region::iterator) override {
    rewritten = true;
  }
  void notifyBlockErased(Block *) override { rewritten = true; }
  void notifyOperationModified(Operation *) override { rewritten = true; }
  void notifyOperationReplaced(Operation *, ValueRange) override { rewritten = true; }
  void notifyOperationErased(Operation *) override { rewritten = true; }

  // Whether the driver reported that this run changed the IR.
  bool rewrote() const { return rewritten; }

  // Reports the run on `op` as remarks, the counts and whether it stopped
  // before its fixpoint at that limit, and returns its rewrites.
  uint64_t report(Operation *op, LogicalResult converged, int64_t maxIterations) const {
    auto opts = remark::RemarkOpts::name("patterns").category("idr-canonicalize");
    if (auto symbol = op->getAttrOfType<StringAttr>(SymbolTable::getSymbolAttrName()))
      opts = opts.function(symbol.getValue());
    if (run.total() != 0)
      if (remark::detail::InFlightRemark out = remark::analysis(op->getLoc(), opts))
        run.addMetrics(out);
    if (succeeded(converged))
      return run.total();
    opts.remarkName = "unconverged";
    remark::missed(op->getLoc(), opts)
        << remark::reason("the greedy driver stopped before a fixpoint, at max-iterations={0}",
                          maxIterations);
    return run.total();
  }

private:
  idr::support::PatternCounts run;
  bool rewritten = false;
};

} // namespace idr::canonicalize
