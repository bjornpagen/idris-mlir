// idr.canon:merge: identical regions of a match merge.
export module idr.canon:merge;

import idr.mlir;
import idr.dialect;

import :rebuild;

using namespace mlir;
using namespace idr;

// The pattern is a template that importers instantiate, so it and what it
// calls are the module's own, not local to this unit.
namespace idr::canon {

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

// Operations a case holds, mixed so two cases that differ there are not
// compared body to body. Equal shapes still are: the mix can collide.
uint64_t shape(Block &block) {
  uint64_t hash = block.getNumArguments();
  for (Operation &op : block) {
    hash = hash * 0x9e3779b97f4a7c15ULL +
           reinterpret_cast<uintptr_t>(op.getName().getAsOpaquePointer());
    hash = hash * 0x9e3779b97f4a7c15ULL + op.getNumOperands();
    hash = hash * 0x9e3779b97f4a7c15ULL + op.getNumResults();
  }
  return hash;
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
      llvm::DenseMap<uint64_t, SmallVector<unsigned, 2>> buckets;
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
    rewriter.replaceOp(op, rebuildMatch(rewriter, op, op.getResultTypes(), cases, regions));
    return success();
  }
};

} // namespace idr::canon

export namespace idr::canon {

// Identical regions merge.
template <typename Match>
void addMerge(mlir::RewritePatternSet &results, mlir::MLIRContext *context) {
  results.add<MergeIdenticalRegions<Match>>(context);
}

} // namespace idr::canon
