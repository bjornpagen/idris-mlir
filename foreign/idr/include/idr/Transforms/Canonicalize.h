// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one configuration every canonicalizer this compiler builds runs
// with: upstream's canonicalizer, configured, never a replacement for it.
//
// Region simplification is disabled. The greedy driver would otherwise
// re-simplify the region tree (dead block arguments, dead blocks, block
// merging at its aggressive level) after every pattern iteration, on
// every function, in every round and every inlining iteration; its cost
// grows with the region tree the earlier rounds built, and the passes
// around the canonicalizer (CSE, remove-dead-values, the next round)
// already remove what it would. Nothing here changes which patterns run
// or what they may rewrite: no pattern, fold or constant is skipped.
//
// The rest restates the canonicalizer pass's own defaults, because a
// default GreedyRewriteConfig does not have them: the pass seeds its
// worklist top-down (its `top-down` option defaults to true), where the
// config's traversal defaults to bottom-up. Building the pass from a
// bare config would change the traversal along with the region level.
#ifndef IDR_TRANSFORMS_CANONICALIZE_H
#define IDR_TRANSFORMS_CANONICALIZE_H

#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/Passes.h"

#include <memory>

namespace idr {

// The configuration of every canonicalizer pass built below, and of any
// greedy rewrite that must agree with one.
inline mlir::GreedyRewriteConfig canonicalizerConfig() {
  return mlir::GreedyRewriteConfig()
      .setUseTopDownTraversal()
      .setRegionSimplificationLevel(mlir::GreedySimplifyRegionLevel::Disabled);
}

// Upstream's canonicalizer pass under canonicalizerConfig(). Every
// canonicalizer in a pipeline of ours is built here, so that the
// configuration has one place to change.
inline std::unique_ptr<mlir::Pass> createCanonicalizerPass() {
  return mlir::createCanonicalizerPass(canonicalizerConfig());
}

} // namespace idr

#endif // IDR_TRANSFORMS_CANONICALIZE_H
