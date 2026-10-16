// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The canonicalizer of every pipeline of ours (idr/Transforms/
// Canonicalize.h): the dialects' and ops' canonicalization patterns under
// upstream's greedy driver, the call-aware ones bound to the pass's table
// (lib/IR/Canon/Callees.cpp).

#include "idr/Transforms/Canonicalize.h"

#include "idr/IR/Canon.h"
#include "idr/IR/Flow.h"
#include "idr/Support/Actions.h"

#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Rewrite/FrozenRewritePatternSet.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include <memory>

namespace idr {
#define GEN_PASS_DEF_IDRCANONICALIZE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// idr-canonicalize makes one greedy run of its patterns over an op; the
// unit is the op the pass runs on.
struct CanonicalizeRunAction : idr::support::TaggedAction<CanonicalizeRunAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-canonicalize-run";
};

GreedyRewriteConfig canonicalizerConfig() {
  return GreedyRewriteConfig()
      .setUseTopDownTraversal()
      .setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled);
}

// The pass of the registry's entry (Passes.td), whose options and
// statistics its generated base holds.
struct Canonicalizer : idr::impl::IdrCanonicalizeBase<Canonicalizer> {
  explicit Canonicalizer(const idr::CalleeEffects *table) : callees(table) {}
  // A copy for another thread or pipeline shares the frozen patterns, which
  // keep nothing between attempts; its statistics are its own, and the
  // pass manager copies its options.
  Canonicalizer(const Canonicalizer &other)
      : IdrCanonicalizeBase(other), callees(other.callees), patterns(other.patterns) {}

  // The patterns as upstream's canonicalizer collects them, every loaded
  // dialect's and every registered op's, then the call-aware ones given
  // this pass's table in place, so that the order of the patterns of each
  // op is its hook's.
  LogicalResult initialize(MLIRContext *context) override {
    RewritePatternSet set(context);
    for (Dialect *dialect : context->getLoadedDialects())
      dialect->getCanonicalizationPatterns(set);
    for (RegisteredOperationName op : context->getRegisteredOperations())
      op.getCanonicalizationPatterns(set, context);
    idr::canon::bindCallees(set, callees);
    patterns = std::make_shared<const FrozenRewritePatternSet>(std::move(set));
    return success();
  }

  // A spent limit leaves the function less canonical, never refused: the
  // statistic counts it. Only a test, which states that the patterns
  // converge on its input, makes it a failure.
  void runOnOperation() override {
    (void)idr::support::perform<CanonicalizeRunAction>(getOperation(), [&] {
      if (succeeded(applyPatternsGreedily(getOperation(), *patterns, canonicalizerConfig())))
        return;
      ++notConverged;
      if (!testConvergence)
        return;
      getOperation()->emitError("canonicalization did not converge on this ")
          << getOperation()->getName()
          << ": a pattern undoes another, or matches again after a change no rewrite reported";
      signalPassFailure();
    });
  }

  const idr::CalleeEffects *callees;
  std::shared_ptr<const FrozenRewritePatternSet> patterns;
};

} // namespace

std::unique_ptr<Pass> idr::createCanonicalizerPass(const CalleeEffects *callees) {
  return std::make_unique<Canonicalizer>(callees);
}

