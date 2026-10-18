// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A match rebuilt with other results, fewer cases or another default
// (MatchOpInterface::rebuild), which every canonicalization that changes a
// match's shape makes. The kept cases are named by their indices, and their
// regions follow from them; the default is the one region given apart. A
// match carries no discardable attribute, so the rebuilt one has nothing to
// take over.

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;
using namespace idr;

namespace {

// Moves the regions of the cases `kept` of `from`, in that order, into the
// case regions of `to`, and `defaultRegion` into its default: an empty
// default moves nothing.
void moveRegions(RewriterBase &rewriter, MatchOpInterface from, MatchOpInterface to,
                 ArrayRef<unsigned> kept, Region *defaultRegion) {
  for (auto [index, at] : llvm::enumerate(kept)) {
    Region &into = to.getCaseRegion(static_cast<unsigned>(index));
    rewriter.inlineRegionBefore(from.getCaseRegion(at), into, into.end());
  }
  Region &fallback = to.getDefaultRegion();
  rewriter.inlineRegionBefore(*defaultRegion, fallback, fallback.end());
}

} // namespace

// The rebuilt match goes where the one it replaces is, whatever op the
// pattern that rebuilds it is rooted at. Its keys are the kept cases'
// tags.
Operation *MatchOp::rebuild(RewriterBase &rewriter, TypeRange results,
                            ArrayRef<unsigned> keptCases, Region *defaultRegion) {
  rewriter.setInsertionPoint(*this);
  auto fresh = MatchOp::create(
      rewriter, getLoc(), results, getScrutinee(),
      llvm::map_to_vector(keptCases, [&](unsigned at) { return getCaseTag(at); }));
  moveRegions(rewriter, *this, fresh, keptCases, defaultRegion);
  return fresh;
}

// Its keys are the kept cases' literals.
Operation *MatchLitOp::rebuild(RewriterBase &rewriter, TypeRange results,
                               ArrayRef<unsigned> keptCases, Region *defaultRegion) {
  rewriter.setInsertionPoint(*this);
  ArrayAttr all = getCases();
  auto fresh = MatchLitOp::create(
      rewriter, getLoc(), results, getScrutinee(),
      rewriter.getArrayAttr(
          llvm::map_to_vector(keptCases, [&](unsigned at) -> Attribute { return all[at]; })));
  moveRegions(rewriter, *this, fresh, keptCases, defaultRegion);
  return fresh;
}
