// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The canonicalization patterns of idr.match and idr.match_lit, which their
// getCanonicalizationPatterns add after upstream's region patterns, and how
// a match whose taken region is known is replaced by it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

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

// A match that can take no region that yields never completes, so nothing
// after it in its block runs: that block, a region of another match or a
// function body, ends in ub.unreachable right after it, as a region does
// after a crash. The regions it can take are all of them, or the one its
// constant scrutinee selects, whatever the others do. Case-of-case copies a
// consumer into every region, so one region of a match may yield the result
// of a match that never completes, followed by what consumes it there.
// A function body has several blocks after the inliner takes in a callee
// that never returns: a value after the match that another block reads
// keeps the block as it is, since erasing it would leave that read with no
// definition.
template <typename Match>
struct EndAfterNoYield : OpRewritePattern<Match> {
  using OpRewritePattern<Match>::OpRewritePattern;
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    auto neverCompletes = [](Region &region) {
      return !region.empty() && isa<ub::UnreachableOp>(region.front().getTerminator());
    };
    Attribute scrutinee;
    Region *taken = matchPattern(op->getOperand(0), m_Constant(&scrutinee)) ? op.getTakenRegion(scrutinee)
                                                                            : nullptr;
    if (taken ? !neverCompletes(*taken) : !llvm::all_of(op->getRegions(), neverCompletes))
      return failure();
    Block *block = op->getBlock();
    if (!isa<MatchOp, MatchLitOp, idr::FuncOp>(block->getParentOp()) ||
        isa<ub::UnreachableOp>(op->getNextNode()))
      return failure();
    for (Operation *after = op->getNextNode(); after; after = after->getNextNode())
      if (after->isUsedOutsideOfBlock(block))
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

namespace idr::canon {

// A case's argument is the declared field at the scrutinee's grade; read
// from the value seen through a linear position, it is the field at that
// value's grade, which the scrutinee's data type says, and the read is then
// held as the argument.
Value readField(OpBuilder &builder, Location loc, Value value) {
  auto arg = cast<BlockArgument>(value);
  auto match = cast<MatchOp>(arg.getOwner()->getParentOp());
  unsigned region = arg.getOwner()->getParent()->getRegionNumber();
  if (region >= match.getCases().size())
    return match.getScrutinee();
  auto ctor = cast<FlatSymbolRefAttr>(match.getCases()[region]);
  Value source = throughLinear(match.getScrutinee());
  const Ctor &declared = match.getDataType().getCtor(match.getCaseTag(region));
  Type type = fieldType(source.getType(), declared.fields[arg.getArgNumber()]);
  Value field = FieldOp::create(builder, loc, type, source, ctor,
                                builder.getI64IntegerAttr(arg.getArgNumber()));
  return heldAs(builder, loc, field, arg.getType());
}

// One whose value entered its grade from a plain value reads that value's
// fields.
LogicalResult readsPlainValue(Operation *op) {
  auto match = dyn_cast<MatchOp>(op);
  return success(!match ||
                 quantityOf(throughLinear(match.getScrutinee()).getType()) != Quantity::One);
}

void addMatchPatterns(RewritePatternSet &results, MLIRContext *context) {
  populate<MatchOp>(results, context);
}

void addMatchLitPatterns(RewritePatternSet &results, MLIRContext *context) {
  populate<MatchLitOp>(results, context);
  results.add<DropEmptyStringCase>(context);
}

} // namespace idr::canon
