// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Case-of-case. The single consumer of a result of a match, another match
// included, moves into every region that yields, when in at least one of
// them it then meets a value it folds or canonicalizes against. The
// consumer moves past no op that does more than compute, and still runs
// exactly once on every path. When it cannot move up to the match, a match
// that only computes moves down to it instead, past the ops between them.
// A call between them, or in the match, does what its own effects say.
// Where the value it meets is yielded by a match a region yields the
// result of, the copy in that region moves on into that match, in the same
// rewrite: a consumer rests where it meets, never a level short of it. A
// constructor resting a level short is one the match yields and its one
// reader only takes apart, which the match's own canonicalization moves
// back out, and the two would move it for ever.
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

// Rooted at a match, as a canonicalization of the match ops is: the
// driver tries it when the match is made or changed, at its seeding of
// every op, and again whenever anything under the match changes, since
// a change requeues its ancestors. From the match it reads each result's
// consumer as it then is. A consumer that does more than compute leaves
// the ops between the match and its place, and those ops whose own
// question spans it are tried again.
struct SinkConsumer : OpInterfaceRewritePattern<MatchOpInterface> {
  explicit SinkConsumer(MLIRContext *context)
      : OpInterfaceRewritePattern(context, PatternBenefit(1)) {
    setDebugName("idr-sink-consumer");
  }

  LogicalResult matchAndRewrite(MatchOpInterface match, PatternRewriter &rewriter) const final {
    for (OpResult result : match->getResults())
      if (Operation *consumer = candidate(result); consumer && moves(match, consumer, rewriter))
        return success();
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

  // Moves `consumer` into `match`, raising the one or lowering the other,
  // and each copy on into the match its region yields the result of where
  // it meets there; whether it could.
  static bool moves(MatchOpInterface match, Operation *consumer, PatternRewriter &rewriter) {
    if (canRaise(match, consumer)) {
      // A consumer that does more than compute stood between each op it
      // moves across and a partner after it. It moves only past ops that
      // compute, which canRaise walked already. A match moved down only
      // computes, and stood between nothing.
      if (!onlyAllocates(consumer))
        canon::retryBetween(rewriter,
                            {std::next(match->getIterator()), consumer->getIterator()});
    } else if (canLower(match, consumer)) {
      rewriter.moveOpBefore(match, consumer);
    } else {
      return false;
    }
    for (Operation *copy : sink(match, consumer, rewriter))
      for (Value operand : copy->getOperands()) {
        auto result = dyn_cast<OpResult>(operand);
        auto inner = result ? dyn_cast<MatchOpInterface>(result.getOwner()) : MatchOpInterface();
        if (inner && candidate(result) == copy) {
          moves(inner, copy, rewriter);
          break;
        }
      }
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
  // consumer before each yield, the copies given back. A result the
  // consumer alone read goes: it is the copies' now, each region's copy
  // the one use there of what the region yielded as it, so that a copy
  // whose region yielded it a match's result moves on into that match. An
  // empty default runs nothing, and a region that ends in ub.unreachable
  // yields nothing to consume.
  static SmallVector<Operation *> sink(MatchOpInterface match, Operation *consumer,
                                       PatternRewriter &rewriter) {
    SmallVector<unsigned> kept;
    SmallVector<Type> types;
    for (OpResult result : match->getResults())
      if (llvm::any_of(result.getUsers(), [&](Operation *user) { return user != consumer; })) {
        kept.push_back(result.getResultNumber());
        types.push_back(result.getType());
      }
    llvm::append_range(types, consumer->getResultTypes());
    Operation *fresh =
        match.rebuild(rewriter, types, llvm::to_vector(llvm::seq(match.getNumCases())),
                      &match.getDefaultRegion());
    SmallVector<Operation *> copies;
    for (Region &region : fresh->getRegions()) {
      auto yield = region.empty() ? YieldOp() : dyn_cast<YieldOp>(region.front().getTerminator());
      if (!yield)
        continue;
      IRMapping mapping;
      mapping.map(match->getResults(), yield.getOperands());
      rewriter.setInsertionPoint(yield);
      Operation *copy = rewriter.clone(*consumer, mapping);
      SmallVector<Value> operands;
      for (unsigned index : kept)
        operands.push_back(yield.getOperand(index));
      llvm::append_range(operands, copy->getResults());
      rewriter.modifyOpInPlace(yield, [&] { yield->setOperands(operands); });
      copies.push_back(copy);
    }
    rewriter.replaceOp(consumer, fresh->getResults().drop_front(kept.size()));
    for (auto [at, index] : llvm::enumerate(kept))
      rewriter.replaceAllUsesWith(match->getResult(index),
                                  fresh->getResult(static_cast<unsigned>(at)));
    rewriter.eraseOp(match);
    return copies;
  }
};

} // namespace

namespace idr::canon {

void addCaseOfCase(RewritePatternSet &results, MLIRContext *context) {
  results.add<SinkConsumer>(context);
}

} // namespace idr::canon
