// idr-canonicalize: canonicalize, with its rewrites counted.
//
// The patterns are those canonicalize collects, from every dialect loaded
// when the pass is initialized and every registered operation, and the
// greedy driver runs with canonicalize's configuration: top-down, region
// simplification at Normal, and this pass's iteration budget. A listener
// counts the patterns that apply, so the IR is what canonicalize leaves.
// The totals are statistics. As for canonicalize, stopping early is no
// failure unless test-convergence asks for one.
//
// A run that rewrites nothing preserves every analysis. That skips the
// walk of every nested operation. A run that rewrites is verified.

#include "idr/Idr.h"

#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

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
  // copy shares the patterns collected for the pass it copies. Each run
  // builds its own driver, listener and change flag. A copy of a pass that
  // was not initialized is initialized in turn.
  Canonicalize(const Canonicalize &other)
      : IdrCanonicalizeBase(other), patterns(other.patterns) {}

  LogicalResult initialize(MLIRContext *context) override {
    if (patterns)
      return success();
    RewritePatternSet owning(context);
    for (Dialect *dialect : context->getLoadedDialects())
      dialect->getCanonicalizationPatterns(owning);
    for (RegisteredOperationName op : context->getRegisteredOperations())
      op.getCanonicalizationPatterns(owning, context);
    patterns.emplace(std::move(owning));
    return success();
  }

  void runOnOperation() override {
    Operation *op = getOperation();
    auto run = [&] {
      if (!patterns) {
        op->emitError() << "idr-canonicalize: patterns were not collected";
        return signalPassFailure();
      }
      // Top-down and region simplification at Normal: canonicalize's
      // configuration. The iteration budget is this pass's. The listener,
      // the configuration and the change flag are locals of this run. A
      // copy of the pass shares the patterns collected at initialization.
      // Constant uniquing while the worklist is built does not start
      // another iteration, and the listener is told of it. A rewrite is
      // verified. A run the driver and the listener both leave untouched
      // preserves every analysis, which skips the walk of every nested
      // operation.
      idr::canonicalize::Counter counter;
      GreedyRewriteConfig config;
      config.setUseTopDownTraversal(true)
          .setRegionSimplificationLevel(GreedySimplifyRegionLevel::Normal)
          .setMaxIterations(maxIterations)
          .setListener(&counter);
      bool changed = false;
      LogicalResult converged = applyPatternsGreedily(op, *patterns, config, &changed);
      numRewrites += counter.report(op, converged, maxIterations);
      if (!changed && !counter.rewrote())
        markAllAnalysesPreserved();
      if (succeeded(converged))
        return;
      ++numUnconverged;
      if (testConvergence)
        signalPassFailure();
    };
    // One scope for a run on the symbol table itself. A run on each
    // function uses a scope a caller already opened (idr-inline does) and
    // does not open another: two functions at once would each open a memo,
    // and opening one per function would scan the module that many times.
    // Data declarations do not change, so the deadness test of a call
    // remembers whether a type may hold a closure.
    if (op->getContext()->getLoadedDialect<idr::IdrDialect>() &&
        SymbolTable::getNearestSymbolTable(op) == op) {
      SymbolTable table(op);
      idr::SymbolScope scope(op, table);
      idr::HoldMemo memo(op->getContext());
      run();
      return;
    }
    run();
  }

  std::optional<FrozenRewritePatternSet> patterns;
};

} // namespace
