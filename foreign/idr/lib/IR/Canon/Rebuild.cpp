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

#include <type_traits>

using namespace mlir;
using namespace idr;

namespace {

// The cases of `op` at the positions `keep`, in that order, as its builder
// takes them: a literal match's literals as an array attribute, a
// constructor match's tags as they are held.
template <typename Match>
auto casesAt(Builder &builder, Match op, ArrayRef<unsigned> keep) {
  auto all = op.getCases();
  using Case = std::remove_cvref_t<decltype(all[0])>;
  SmallVector<Case> cases = llvm::map_to_vector(keep, [&](unsigned at) -> Case { return all[at]; });
  if constexpr (std::is_convertible_v<Case, Attribute>)
    return builder.getArrayAttr(SmallVector<Attribute>(cases.begin(), cases.end()));
  else
    return cases;
}

} // namespace

namespace idr::canon {

template <typename Match>
Match rebuildMatch(RewriterBase &rewriter, Match op, TypeRange types, ArrayRef<unsigned> cases,
                   ArrayRef<Region *> regions) {
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
  rewriter.setInsertionPoint(match);
  return llvm::TypeSwitch<Operation *, Operation *>(match).Case<MatchOp, MatchLitOp>(
      [&](auto op) -> Operation * {
        SmallVector<Region *> regions =
            llvm::map_to_vector(op->getRegions(), [](Region &region) { return &region; });
        SmallVector<unsigned> cases = llvm::to_vector(
            llvm::seq<unsigned>(0, static_cast<unsigned>(op.getCases().size())));
        return rebuildMatch(rewriter, op, types, cases, regions);
      });
}

} // namespace idr::canon
