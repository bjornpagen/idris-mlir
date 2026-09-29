// Identical regions of a match merge.

#include "Dialect/Canonicalize/Matches.h"

using namespace mlir;
using namespace idr;

namespace {

// Whether two regions do the same thing without reading their arguments.
bool sameBody(Region &a, Region &b) {
  Block &x = a.front(), &y = b.front();
  auto unused = [](Block &block) {
    return llvm::all_of(block.getArguments(), [](BlockArgument arg) { return arg.use_empty(); });
  };
  if (!unused(x) || !unused(y) || x.getOperations().size() != y.getOperations().size())
    return false;
  DenseMap<Value, Value> same;
  return llvm::all_of_zip(x, y, [&](Operation &l, Operation &r) {
    return OperationEquivalence::isEquivalentTo(
        &l, &r,
        [&](Value lv, Value rv) { return success(lv == rv || same.lookup(lv) == rv); },
        [&](Value lv, Value rv) { same[lv] = rv; }, OperationEquivalence::IgnoreLocations);
  });
}

// A case that does what the default does is left to the default, and
// without a default, cases that do the same become it.
template <typename Match>
struct MergeIdenticalRegions : OpRewritePattern<Match> {
  using OpRewritePattern<Match>::OpRewritePattern;
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    unsigned count = static_cast<unsigned>(op.getCases().size());
    Region *fallback = op.getDefaultRegion();
    if (!fallback)
      for (unsigned i = 0; i < count && !fallback; ++i)
        for (unsigned j = i + 1; j < count && !fallback; ++j)
          if (sameBody(op.getCaseRegion(i), op.getCaseRegion(j)))
            fallback = &op.getCaseRegion(i);
    if (!fallback)
      return failure();
    SmallVector<Attribute> cases;
    SmallVector<Region *> regions;
    for (unsigned i = 0; i < count; ++i)
      if (&op.getCaseRegion(i) != fallback && !sameBody(op.getCaseRegion(i), *fallback)) {
        cases.push_back(op.getCases()[i]);
        regions.push_back(&op.getCaseRegion(i));
      }
    if (regions.size() + 1 == op.getRegions().size() && fallback == op.getDefaultRegion())
      return failure();
    // The new default takes no arguments; the old region's are unused.
    rewriter.modifyOpInPlace(op, [&] {
      fallback->front().eraseArguments(0, fallback->getNumArguments());
    });
    regions.push_back(fallback);
    rewriter.replaceOp(op, canon::rebuildMatch(rewriter, op, op.getResultTypes(), cases, regions));
    return success();
  }
};

} // namespace

template <typename Match> void canon::addMerge(RewritePatternSet &results, MLIRContext *context) {
  results.add<MergeIdenticalRegions<Match>>(context);
}

template void canon::addMerge<MatchOp>(RewritePatternSet &, MLIRContext *);
template void canon::addMerge<MatchLitOp>(RewritePatternSet &, MLIRContext *);
