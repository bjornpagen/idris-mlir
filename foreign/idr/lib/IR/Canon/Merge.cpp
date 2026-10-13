// Identical regions of a match merge. Upstream's region patterns merge
// results, not regions, and a match region is one block, which the block
// merging of region simplification never sees two of.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"

#include "mlir/IR/OperationSupport.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

// Whether two regions do the same thing without reading their arguments.
bool sameBody(Region &a, Region &b) {
  Block &x = a.front(), &y = b.front();
  auto unused = [](Block &block) {
    return llvm::all_of(block.getArguments(), [](BlockArgument arg) { return arg.use_empty(); });
  };
  // Length is part of the comparison below. The list's size walks every
  // operation, and the comparison walks them again.
  if (!unused(x) || !unused(y))
    return false;
  DenseMap<Value, Value> same;
  return llvm::all_of_zip(x, y, [&](Operation &l, Operation &r) {
    return OperationEquivalence::isEquivalentTo(
        &l, &r,
        [&](Value lv, Value rv) { return success(lv == rv || same.lookup(lv) == rv); },
        [&](Value lv, Value rv) { same[lv] = rv; }, OperationEquivalence::IgnoreLocations);
  });
}

// The operations a case holds, hashed as the comparison below compares
// them but for their regions, so two cases that differ there are not
// compared body to body. Equal shapes still are: the hash can collide.
llvm::hash_code shape(Block &block) {
  return llvm::hash_combine(
      block.getNumArguments(), llvm::hash_combine_range(llvm::map_range(block, [](Operation &op) {
        return OperationEquivalence::computeHash(&op, OperationEquivalence::ignoreHashValue,
                                                 OperationEquivalence::ignoreHashValue,
                                                 OperationEquivalence::IgnoreLocations);
      })));
}

// A case that does what the default does is left to the default, and
// without a default, cases that do the same become it.
template <typename Match>
struct MergeIdenticalRegions : OpRewritePattern<Match> {
  using OpRewritePattern<Match>::OpRewritePattern;
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    unsigned count = static_cast<unsigned>(op.getCases().size());
    Region *fallback = op.getDefaultRegion();
    // Every pair of cases, when nothing is a default yet. A match with many
    // cases would compare each body with every other; cases whose operations
    // differ cannot be that pair.
    if (!fallback) {
      llvm::DenseMap<llvm::hash_code, SmallVector<unsigned, 2>> buckets;
      for (unsigned i = 0; i < count; ++i)
        buckets[shape(op.getCaseRegion(i).front())].push_back(i);
      unsigned best = count;
      for (auto &bucket : buckets) {
        ArrayRef<unsigned> ids = bucket.second;
        for (unsigned a = 0; a < ids.size() && ids[a] < best; ++a)
          for (unsigned b = a + 1; b < ids.size(); ++b)
            if (sameBody(op.getCaseRegion(ids[a]), op.getCaseRegion(ids[b]))) {
              best = ids[a];
              fallback = &op.getCaseRegion(ids[a]);
              break;
            }
      }
    }
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

namespace idr::canon {

template <typename Match>
void addMerge(RewritePatternSet &results, MLIRContext *context) {
  results.add<MergeIdenticalRegions<Match>>(context);
}

template void addMerge<MatchOp>(RewritePatternSet &, MLIRContext *);
template void addMerge<MatchLitOp>(RewritePatternSet &, MLIRContext *);

} // namespace idr::canon
