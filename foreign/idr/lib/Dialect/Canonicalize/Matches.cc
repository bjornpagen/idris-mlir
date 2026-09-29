// The canonicalization patterns of idr.match and idr.match_lit.

#include "Dialect/Canonicalize/Matches.h"

#include "mlir/Transforms/RegionUtils.h"

using namespace mlir;
using namespace idr;

namespace {

// A string that cannot be empty never takes the case `""`.
struct DropEmptyStringCase : OpRewritePattern<MatchLitOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(MatchLitOp op, PatternRewriter &rewriter) const final {
    auto empty = rewriter.getStringAttr("");
    const auto *it = llvm::find(op.getCases(), empty);
    if (it == op.getCases().end() || !knownNonEmpty(op.getScrutinee()))
      return failure();
    auto dropped = static_cast<unsigned>(it - op.getCases().begin());
    SmallVector<Attribute> cases;
    SmallVector<Region *> regions;
    for (unsigned index = 0, count = op->getNumRegions(); index < count; ++index)
      if (index != dropped) {
        if (index < op.getCases().size())
          cases.push_back(op.getCases()[index]);
        regions.push_back(&op->getRegion(index));
      }
    rewriter.replaceOp(op, canon::rebuildMatch(rewriter, op, op.getResultTypes(), cases, regions));
    return success();
  }
};

// A case region's arguments are its constructor's fields.
Value readField(OpBuilder &builder, Location loc, Value value) {
  auto arg = cast<BlockArgument>(value);
  auto match = cast<MatchOp>(arg.getOwner()->getParentOp());
  auto ctor = cast<FlatSymbolRefAttr>(
      match.getCases()[arg.getOwner()->getParent()->getRegionNumber()]);
  return FieldOp::create(builder, loc, arg.getType(), match.getScrutinee(), ctor,
                         builder.getI64IntegerAttr(arg.getArgNumber()));
}

// Upstream's region patterns, as scf.index_switch uses them: results no
// region needs drop, and a match whose taken region is known (a constant or
// an idr.con scrutinee, or one region left) is replaced by that region, whose
// arguments become idr.field reads that fold.
template <typename Match>
void populate(RewritePatternSet &results, MLIRContext *context,
              NonSuccessorInputReplacementBuilderFn replacement) {
  populateRegionBranchOpInterfaceCanonicalizationPatterns(results, Match::getOperationName());
  populateRegionBranchOpInterfaceInliningPattern(results, Match::getOperationName(),
                                                 replacement);
  canon::addMerge<Match>(results, context);
  canon::addCaseOfCase<Match>(results, context);
  canon::addSink<Match>(results, context);
}

} // namespace

void MatchOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  populate<MatchOp>(results, context, readField);
}

void MatchLitOp::getCanonicalizationPatterns(RewritePatternSet &results,
                                             MLIRContext *context) {
  populate<MatchLitOp>(results, context, mlir::detail::defaultReplBuilderFn);
  results.add<DropEmptyStringCase>(context);
}
