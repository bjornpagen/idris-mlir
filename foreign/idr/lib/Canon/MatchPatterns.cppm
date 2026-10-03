// idr.canon:matchpatterns: the canonicalization patterns of idr.match and
// idr.match_lit, which their getCanonicalizationPatterns add, and how a
// match whose taken region is known is replaced by it.
export module idr.canon:matchpatterns;

import idr.mlir;
import idr.dialect;

import :caseofcase;
import :merge;
import :rebuild;
import :sink;

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

// A default region the match cannot take: its cases name every constructor
// of the data. Idris's case trees carry one for the clauses that follow a
// complete split, and it looks like a path to every analysis.
struct DropCoveredDefault : OpRewritePattern<MatchOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(MatchOp op, PatternRewriter &rewriter) const final {
    if (!op.getDefaultRegion())
      return failure();
    DataOp data = lookupData(op, op.getScrutinee().getType());
    if (!data || op.getCases().size() != llvm::range_size(data.getBody().getOps<CtorOp>()))
      return failure();
    SmallVector<Attribute> cases(op.getCases().begin(), op.getCases().end());
    SmallVector<Region *> regions;
    for (unsigned index = 0, e = static_cast<unsigned>(cases.size()); index < e; ++index)
      regions.push_back(&op.getCaseRegion(index));
    rewriter.replaceOp(op, canon::rebuildMatch(rewriter, op, op.getResultTypes(), cases, regions));
    return success();
  }
};

// A match none of whose regions yields never completes, so nothing after it
// in its block runs: that block, a region of another match, ends in
// ub.unreachable right after it, as a region does after a crash. Case-of-case
// copies a consumer into every region, so one region of a match may yield
// the result of a match that never completes, followed by what consumes it
// there. A function body keeps its return: a body never ends in
// ub.unreachable (PINS.md: inline-unreachable).
template <typename Match>
struct EndAfterNoYield : OpRewritePattern<Match> {
  using OpRewritePattern<Match>::OpRewritePattern;
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    if (llvm::any_of(op->getRegions(), [](Region &region) {
          return region.empty() || !isa<ub::UnreachableOp>(region.front().getTerminator());
        }))
      return failure();
    Block *block = op->getBlock();
    if (!isa<MatchOp, MatchLitOp>(block->getParentOp()) ||
        isa<ub::UnreachableOp>(op->getNextNode()))
      return failure();
    while (&block->back() != op.getOperation())
      rewriter.eraseOp(&block->back());
    rewriter.setInsertionPointToEnd(block);
    ub::UnreachableOp::create(rewriter, op.getLoc());
    return success();
  }
};

// What both matches canonicalize with besides upstream's region patterns,
// which the hooks add first.
template <typename Match>
void populate(RewritePatternSet &results, MLIRContext *context) {
  canon::addMerge<Match>(results, context);
  canon::addCaseOfCase<Match>(results, context);
  canon::addSink<Match>(results, context);
  results.add<EndAfterNoYield<Match>>(context);
}

} // namespace

export namespace idr::canon {

// A case region's arguments are its constructor's fields, read from the
// value the scrutinee entered its grade from and held as the region binds
// them; the default region's argument is the scrutinee itself.
Value readField(OpBuilder &builder, Location loc, Value value) {
  auto arg = cast<BlockArgument>(value);
  auto match = cast<MatchOp>(arg.getOwner()->getParentOp());
  unsigned region = arg.getOwner()->getParent()->getRegionNumber();
  if (region >= match.getCases().size())
    return match.getScrutinee();
  auto ctor = cast<FlatSymbolRefAttr>(match.getCases()[region]);
  Value source = throughLinear(match.getScrutinee());
  CtorOp decl = lookupCtor(lookupData(match, source.getType()), ctor.getValue());
  Value field = FieldOp::create(builder, loc,
                                fieldType(source.getType(), decl.getFieldType(arg.getArgNumber())),
                                source, ctor, builder.getI64IntegerAttr(arg.getArgNumber()));
  return heldAs(builder, loc, field, arg.getType());
}

// A match on a linear value takes it apart, and stays: the value has no
// other reader to read its fields from. One whose value entered its grade
// from a plain value reads that value's fields.
LogicalResult readsPlainValue(Operation *op) {
  auto match = dyn_cast<MatchOp>(op);
  return success(!match ||
                 quantityOf(throughLinear(match.getScrutinee()).getType()) != Quantity::One);
}

// The patterns of idr.match, after upstream's region patterns.
void addMatchPatterns(RewritePatternSet &results, MLIRContext *context) {
  populate<MatchOp>(results, context);
  results.add<DropCoveredDefault>(context);
}

// The patterns of idr.match_lit, after upstream's region patterns.
void addMatchLitPatterns(RewritePatternSet &results, MLIRContext *context) {
  populate<MatchLitOp>(results, context);
  results.add<DropEmptyStringCase>(context);
}

} // namespace idr::canon
