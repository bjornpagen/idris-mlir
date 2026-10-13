// A match rebuilt with other results or regions, which every
// canonicalization that changes a match's shape makes. A match carries no
// discardable attribute, so the rebuilt one has nothing to take over.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

namespace idr::canon {

template <typename Match>
Match rebuildMatch(RewriterBase &rewriter, Match op, TypeRange types,
                   ArrayRef<Attribute> cases, ArrayRef<Region *> regions) {
  auto fresh = Match::create(rewriter, op.getLoc(), types, op.getScrutinee(),
                             rewriter.getArrayAttr(cases),
                             static_cast<unsigned>(regions.size()));
  for (auto [to, from] : llvm::zip(fresh.getRegions(), regions))
    rewriter.inlineRegionBefore(*from, to, to.end());
  return fresh;
}

template MatchOp rebuildMatch<MatchOp>(RewriterBase &, MatchOp, TypeRange,
                                       ArrayRef<Attribute>, ArrayRef<Region *>);
template MatchLitOp rebuildMatch<MatchLitOp>(RewriterBase &, MatchLitOp, TypeRange,
                                             ArrayRef<Attribute>, ArrayRef<Region *>);

Operation *rebuildMatch(RewriterBase &rewriter, Operation *match, TypeRange types) {
  rewriter.setInsertionPoint(match);
  return llvm::TypeSwitch<Operation *, Operation *>(match).Case<MatchOp, MatchLitOp>(
      [&](auto op) -> Operation * {
        SmallVector<Region *> regions =
            llvm::map_to_vector(op->getRegions(), [](Region &region) { return &region; });
        return rebuildMatch(rewriter, op, types, llvm::to_vector(op.getCases()), regions);
      });
}

} // namespace idr::canon
