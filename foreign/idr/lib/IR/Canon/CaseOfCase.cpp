// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Case-of-case. The single consumer of a result of a match, another match
// included, moves into every region that yields, when in at least one of
// them it then meets a value it folds or canonicalizes against. The
// consumer moves past no op that does more than compute, and still runs
// exactly once on every path. When it cannot move up to the match, a match
// that only computes moves down to it instead, past the ops between them.
// A call between them, or in the match, does what its own effects say.
//
// The driver attempts this again for the same match whenever anything
// under it changes. Each attempt asks the question again: it costs the
// match's width twice, and nothing a pattern could keep between attempts
// would be told what changed.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Flow.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/RegionUtils.h"
#include "llvm/ADT/Sequence.h"

using namespace mlir;
using namespace idr;

namespace {

// Tried at every op, so that each change the driver reports reaches it: at
// a match, whose regions changed, each result's consumer; at any other op,
// a consumer made or changed, each match whose result it consumes. A
// consumer that does more than compute leaves the ops between the match
// and its place, and those ops whose own question spans it are tried
// again.
struct SinkConsumer : RewritePattern {
  explicit SinkConsumer(MLIRContext *context)
      : RewritePattern(MatchAnyOpTypeTag(), PatternBenefit(1), context) {
    setDebugName("idr-sink-consumer");
  }

  LogicalResult matchAndRewrite(Operation *op, PatternRewriter &rewriter) const final {
    if (auto match = dyn_cast<MatchOpInterface>(op))
      for (OpResult result : op->getResults())
        if (Operation *consumer = candidate(result); consumer && moves(match, consumer, rewriter))
          return success();
    for (Value operand : op->getOperands()) {
      auto result = dyn_cast<OpResult>(operand);
      auto match = result ? dyn_cast<MatchOpInterface>(result.getOwner()) : MatchOpInterface();
      if (match && candidate(result) == op && moves(match, op, rewriter))
        return success();
    }
    return failure();
  }

private:
  // The single consumer of `result`, a match's, in the match's block, when
  // it would meet in some region a value it folds or canonicalizes against.
  static Operation *candidate(OpResult result) {
    if (!result.hasOneUse())
      return nullptr;
    Operation *consumer = *result.getUsers().begin();
    if (consumer->getBlock() != result.getOwner()->getBlock() ||
        consumer->hasTrait<OpTrait::IsTerminator>())
      return nullptr;
    return canon::meetsInSomeRegion(result, consumer) ? consumer : nullptr;
  }

  // Moves `consumer` into `match`, raising the one or lowering the other;
  // whether it could.
  static bool moves(MatchOpInterface match, Operation *consumer, PatternRewriter &rewriter) {
    if (canRaise(match, consumer)) {
      // A consumer that does more than compute stood between each op it
      // moves across and a partner after it. It moves only past ops that
      // compute, which canRaise walked already. A match moved down only
      // computes, and stood between nothing.
      if (!onlyAllocates(consumer))
        canon::retryBetween(rewriter,
                            {std::next(match->getIterator()), consumer->getIterator()});
      sink(match, consumer, rewriter);
      return true;
    }
    if (!canLower(match, consumer))
      return false;
    rewriter.moveOpBefore(match, consumer);
    sink(match, consumer, rewriter);
    return true;
  }

  // Whether `consumer` can move up to the match: its other operands, and the
  // values its regions use from outside, are the match's results or exist
  // before the match, and every op between them only computes.
  static bool canRaise(Operation *match, Operation *consumer) {
    Block *block = match->getBlock();
    auto before = [&](Value value) {
      Operation *def = value.getDefiningOp();
      return !def || def == match || def->getBlock() != block || def->isBeforeInBlock(match);
    };
    if (!llvm::all_of(consumer->getOperands(), before))
      return false;
    bool captured = true;
    visitUsedValuesDefinedAbove(consumer->getRegions(), [&](OpOperand *use) {
      captured &= before(use->get());
    });
    if (!captured)
      return false;
    for (Operation *between = match->getNextNode(); between != consumer;
         between = between->getNextNode())
      if (!onlyAllocates(between))
        return false;
    return true;
  }

  // Whether the match can move down to `consumer`: it only computes, and
  // nothing between them uses its results. Its operands and the values its
  // regions use exist before it, so they exist before the consumer too.
  static bool canLower(Operation *match, Operation *consumer) {
    if (!onlyAllocates(match))
      return false;
    return llvm::all_of(match->getUsers(), [&](Operation *user) {
      Operation *at = match->getBlock()->findAncestorOpInBlock(*user);
      return at && (at == consumer || consumer->isBeforeInBlock(at));
    });
  }

  // The match with the consumer's results after its own, and a copy of the
  // consumer before each yield. An empty default runs nothing, and a region
  // that ends in ub.unreachable yields nothing to consume.
  static void sink(MatchOpInterface match, Operation *consumer, PatternRewriter &rewriter) {
    unsigned kept = match->getNumResults();
    SmallVector<Type> types(match->getResultTypes());
    llvm::append_range(types, consumer->getResultTypes());
    Operation *fresh =
        match.rebuild(rewriter, types, llvm::to_vector(llvm::seq(match.getNumCases())),
                      &match.getDefaultRegion());
    for (Region &region : fresh->getRegions()) {
      auto yield = region.empty() ? YieldOp() : dyn_cast<YieldOp>(region.front().getTerminator());
      if (!yield)
        continue;
      IRMapping mapping;
      mapping.map(match->getResults(), yield.getOperands());
      rewriter.setInsertionPoint(yield);
      Operation *copy = rewriter.clone(*consumer, mapping);
      rewriter.modifyOpInPlace(yield, [&] {
        yield->insertOperands(yield->getNumOperands(), copy->getResults());
      });
    }
    rewriter.replaceOp(consumer, fresh->getResults().drop_front(kept));
    rewriter.replaceOp(match, fresh->getResults().take_front(kept));
  }
};

} // namespace

namespace idr::canon {

void addCaseOfCase(RewritePatternSet &results, MLIRContext *context) {
  results.add<SinkConsumer>(context);
}

} // namespace idr::canon
