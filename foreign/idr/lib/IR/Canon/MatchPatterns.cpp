// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The canonicalization patterns of idr.match and idr.match_lit, which their
// getCanonicalizationPatterns add after upstream's region patterns, and how
// a match whose taken region is known is replaced by it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Worklist.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

// The literal match on `scrutinee`, or on a string appended of it, that
// has the case `""`: what a string known not to be empty reaches through
// the appends it is part of, which are then not empty either. Each value is
// looked at once.
MatchLitOp emptyCaseAbove(Value scrutinee) {
  OnceWorklist<Value> work;
  work.push(scrutinee);
  while (std::optional<Value> next = work.pop())
    for (Operation *user : next->getUsers()) {
      if (auto match = dyn_cast<MatchLitOp>(user);
          match && match.getScrutinee() == *next &&
          llvm::is_contained(match.getCases(), StringAttr::get(user->getContext(), "")))
        return match;
      if (auto append = dyn_cast<StrAppendOp>(user))
        work.push(append.getResult());
    }
  return {};
}

// A string that cannot be empty never takes the case `""`. Whether it can
// is read down the appends it is built of; a change there reaches the op
// above it alone. So the pattern is tried at every op: at a literal match,
// for its own scrutinee, and at a string known not to be empty, for the
// matches it reaches up through the appends it is part of.
struct DropEmptyStringCase : RewritePattern {
  explicit DropEmptyStringCase(MLIRContext *context)
      : RewritePattern(MatchAnyOpTypeTag(), PatternBenefit(1), context) {
    setDebugName("idr-drop-empty-string-case");
  }

  LogicalResult matchAndRewrite(Operation *root, PatternRewriter &rewriter) const final {
    auto match = dyn_cast<MatchLitOp>(root);
    if (match && knownNonEmpty(match.getScrutinee()) && drop(match, rewriter))
      return success();
    if (root->getNumResults() != 1 || !isa<StrType>(unrestricted(root->getResult(0).getType())) ||
        !knownNonEmpty(root->getResult(0)))
      return failure();
    MatchLitOp above = emptyCaseAbove(root->getResult(0));
    return success(above && drop(above, rewriter));
  }

private:
  // Drops the case `""` of `op`; whether it had one.
  static bool drop(MatchLitOp op, PatternRewriter &rewriter) {
    auto empty = rewriter.getStringAttr("");
    const auto *it = llvm::find(op.getCases(), empty);
    if (it == op.getCases().end())
      return false;
    auto dropped = static_cast<unsigned>(it - op.getCases().begin());
    SmallVector<unsigned> cases;
    SmallVector<Region *> regions;
    for (unsigned index = 0, count = op->getNumRegions(); index < count; ++index)
      if (index != dropped) {
        if (index < op.getCases().size())
          cases.push_back(index);
        regions.push_back(&op->getRegion(index));
      }
    rewriter.replaceOp(op, canon::rebuildMatch(rewriter, op, op.getResultTypes(), cases, regions));
    return true;
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
    Region *taken = matchPattern(op->getOperand(0), m_Constant(&scrutinee))
                        ? op.getTakenRegion(scrutinee)
                        : nullptr;
    if (taken ? !neverCompletes(*taken) : !llvm::all_of(op->getRegions(), neverCompletes))
      return failure();
    Block *block = op->getBlock();
    if (!isa<MatchOp, MatchLitOp, idr::FuncOp>(block->getParentOp()) ||
        isa<ub::UnreachableOp>(op->getNextNode()))
      return failure();
    SmallVector<Operation *> after;
    for (Operation *next = op->getNextNode(); next; next = next->getNextNode()) {
      if (next->isUsedOutsideOfBlock(block))
        return failure();
      after.push_back(next);
    }
    // Users before what they use.
    for (Operation *dead : llvm::reverse(after))
      rewriter.eraseOp(dead);
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
  results.add<EndAfterNoYield<Match>>(context);
}

} // namespace

namespace idr::canon {

// A case's argument is the declared field at the scrutinee's grade; read
// from the value seen through a linear position, it is the field at that
// value's grade, as idr.field reads it, and the read is then held as the
// argument.
Value readField(OpBuilder &builder, Location loc, Value value) {
  auto arg = cast<BlockArgument>(value);
  auto match = cast<MatchOp>(arg.getOwner()->getParentOp());
  unsigned region = arg.getOwner()->getParent()->getRegionNumber();
  if (region >= match.getCases().size())
    return match.getScrutinee();
  Value field = FieldOp::create(builder, loc, throughLinear(match.getScrutinee()),
                                match.getCaseTag(region), arg.getArgNumber());
  return heldAs(builder, loc, field, arg.getType());
}

// One whose value entered its grade from a plain value reads that value's
// fields.
LogicalResult readsPlainValue(Operation *op) {
  auto match = dyn_cast<MatchOp>(op);
  return success(!match ||
                 quantityOf(throughLinear(match.getScrutinee()).getType()) != Quantity::One);
}

// Case-of-case and sinking are tried at every op, so the one hook adds
// them for both matches.
void addMatchPatterns(RewritePatternSet &results, MLIRContext *context) {
  populate<MatchOp>(results, context);
  canon::addCaseOfCase(results, context);
  canon::addSink(results, context);
}

void addMatchLitPatterns(RewritePatternSet &results, MLIRContext *context) {
  populate<MatchLitOp>(results, context);
  results.add<DropEmptyStringCase>(context);
}

} // namespace idr::canon
