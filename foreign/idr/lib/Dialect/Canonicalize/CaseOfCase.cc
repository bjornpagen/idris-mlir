// Case-of-case: the single consumer of a result of a match, another match
// included, moves into every region that yields, when in at least one of
// them it then meets a value it folds or canonicalizes against. The
// consumer moves past no op that does more than compute, and still runs
// exactly once on every path. When it cannot move up to the match, a match
// that only computes moves down to it instead, past the ops between them.

#include "Dialect/Canonicalize/Matches.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/Transforms/RegionUtils.h"


using namespace mlir;
using namespace idr;

namespace {

template <typename Match>
struct SinkConsumer : OpRewritePattern<Match> {
  explicit SinkConsumer(MLIRContext *context) : OpRewritePattern<Match>(context) {
    this->setDebugName("idr-sink-consumer");
  }
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    for (OpResult result : op->getResults()) {
      Operation *consumer = candidate(op, result);
      if (!consumer)
        continue;
      if (canRaise(op, consumer))
        return sink(op, consumer, rewriter);
      if (canLower(op, consumer)) {
        rewriter.moveOpBefore(op, consumer);
        return sink(op, consumer, rewriter);
      }
    }
    return failure();
  }

private:
  // The single consumer of `result`, in the match's block, when it would
  // meet in some region a value it folds or canonicalizes against.
  static Operation *candidate(Match op, OpResult result) {
    if (!result.hasOneUse())
      return nullptr;
    Operation *consumer = *result.getUsers().begin();
    if (consumer->getBlock() != op->getBlock() || consumer->hasTrait<OpTrait::IsTerminator>())
      return nullptr;
    return canon::meetsInSomeRegion(result, consumer) ? consumer : nullptr;
  }

  // Whether `consumer` can move up to the match: its other operands, and the
  // values its regions use from outside, are the match's results or exist
  // before the match, and every op between them only computes.
  static bool canRaise(Match op, Operation *consumer) {
    Block *block = op->getBlock();
    auto before = [&](Value value) {
      Operation *def = value.getDefiningOp();
      return !def || def == op || def->getBlock() != block || def->isBeforeInBlock(op);
    };
    if (!llvm::all_of(consumer->getOperands(), before))
      return false;
    bool captured = true;
    visitUsedValuesDefinedAbove(consumer->getRegions(), [&](OpOperand *use) {
      captured &= before(use->get());
    });
    if (!captured)
      return false;
    for (Operation *between = op->getNextNode(); between != consumer;
         between = between->getNextNode())
      if (!onlyAllocates(between))
        return false;
    return true;
  }

  // Whether the match can move down to `consumer`: it only computes, and
  // nothing between them uses its results. Its operands and the values its
  // regions use exist before it, so they exist before the consumer too.
  static bool canLower(Match op, Operation *consumer) {
    if (!onlyAllocates(op))
      return false;
    return llvm::all_of(op->getUsers(), [&](Operation *user) {
      Operation *at = op->getBlock()->findAncestorOpInBlock(*user);
      return at && (at == consumer || consumer->isBeforeInBlock(at));
    });
  }

  static LogicalResult sink(Match op, Operation *consumer, PatternRewriter &rewriter) {
    unsigned kept = op->getNumResults();
    SmallVector<Type> types(op->getResultTypes());
    llvm::append_range(types, consumer->getResultTypes());
    SmallVector<Region *> regions = llvm::map_to_vector(
        op.getRegions(), [](Region &region) { return &region; });
    rewriter.setInsertionPoint(op);
    Match fresh = canon::rebuildMatch(rewriter, op, types, llvm::to_vector(op.getCases()), regions);
    for (Region &region : fresh.getRegions()) {
      auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
      if (!yield)
        continue;
      IRMapping mapping;
      mapping.map(op->getResults(), yield.getOperands());
      rewriter.setInsertionPoint(yield);
      Operation *copy = rewriter.clone(*consumer, mapping);
      rewriter.modifyOpInPlace(yield, [&] {
        yield->insertOperands(yield->getNumOperands(), copy->getResults());
      });
    }
    rewriter.replaceOp(consumer, fresh->getResults().drop_front(kept));
    rewriter.replaceOp(op, fresh->getResults().take_front(kept));
    return success();
  }
};

} // namespace

template <typename Match>
void canon::addCaseOfCase(RewritePatternSet &results, MLIRContext *context) {
  results.add<SinkConsumer<Match>>(context);
}

template void canon::addCaseOfCase<MatchOp>(RewritePatternSet &, MLIRContext *);
template void canon::addCaseOfCase<MatchLitOp>(RewritePatternSet &, MLIRContext *);
