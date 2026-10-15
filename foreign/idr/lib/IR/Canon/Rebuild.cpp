// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A match rebuilt with other results or regions, which every
// canonicalization that changes a match's shape makes. A match carries no
// discardable attribute, so the rebuilt one has nothing to take over.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/TypeSwitch.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"

using namespace mlir;
using namespace idr;

namespace {

// The cases of `op` at the positions `keep`, in that order, as its builder
// takes them: a constructor match's tags, a literal match's literals as an
// array attribute.
SmallVector<Tag> casesAt(Builder &, MatchOp op, ArrayRef<unsigned> keep) {
  return llvm::map_to_vector(keep, [&](unsigned at) { return op.getCaseTag(at); });
}

ArrayAttr casesAt(Builder &builder, MatchLitOp op, ArrayRef<unsigned> keep) {
  ArrayAttr all = op.getCases();
  return builder.getArrayAttr(
      llvm::map_to_vector(keep, [&](unsigned at) -> Attribute { return all[at]; }));
}

} // namespace

namespace idr::canon {

// The rebuilt match goes where the one it replaces is, whatever op the
// pattern that rebuilds it is rooted at.
template <typename Match>
Match rebuildMatch(RewriterBase &rewriter, Match op, TypeRange types, ArrayRef<unsigned> cases,
                   ArrayRef<Region *> regions) {
  rewriter.setInsertionPoint(op);
  auto fresh = Match::create(rewriter, op.getLoc(), types, op.getScrutinee(),
                             casesAt(rewriter, op, cases), static_cast<unsigned>(regions.size()));
  for (auto [to, from] : llvm::zip(fresh.getRegions(), regions))
    rewriter.inlineRegionBefore(*from, to, to.end());
  return fresh;
}

template MatchOp rebuildMatch<MatchOp>(RewriterBase &, MatchOp, TypeRange, ArrayRef<unsigned>,
                                       ArrayRef<Region *>);
template MatchLitOp rebuildMatch<MatchLitOp>(RewriterBase &, MatchLitOp, TypeRange,
                                             ArrayRef<unsigned>, ArrayRef<Region *>);

Operation *rebuildMatch(RewriterBase &rewriter, Operation *match, TypeRange types) {
  return llvm::TypeSwitch<Operation *, Operation *>(match)
      .Case<MatchOp, MatchLitOp>([&](auto op) -> Operation * {
        SmallVector<Region *> regions =
            llvm::map_to_vector(op->getRegions(), [](Region &region) { return &region; });
        SmallVector<unsigned> cases = llvm::to_vector(
            llvm::seq<unsigned>(0, static_cast<unsigned>(op.getCases().size())));
        return rebuildMatch(rewriter, op, types, cases, regions);
      })
      .Default([](Operation *other) -> Operation * {
        llvm::report_fatal_error(llvm::Twine("internal error: a match rebuilt from ") +
                                 other->getName().getStringRef());
      });
}

} // namespace idr::canon
