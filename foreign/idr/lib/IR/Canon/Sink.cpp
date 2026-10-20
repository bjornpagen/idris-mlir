// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A value computed in the match's block that only the match's regions use
// moves into each region that uses it, when there it meets a consumer that
// folds against it: output of a string it builds, or a consumer a match of
// its moves into (case-of-case). Only one region runs, so the value is
// still computed at most once. A constructor, a closure or a change of
// grade (an entry into a linear type, its use) moves into the regions that
// use it without a consumer to meet: built where it is used, a cell is
// built only on the paths that use it, and after the reads there of the
// fields it takes, which then need no count of their own; entered on a
// path that does not use it, a linear value would be left there for
// counting to drop. Such a copy is one op, and no consumer follows it in.
//
// A value that only computes may run on fewer paths. One that may crash or
// not return moves only when every region uses it and every op between it
// and the match only computes: every path still computes it, before
// anything it could hide. A force is such a value until it is a call: it
// runs its suspension's code, which may crash or not return as a call's
// may, and its effects say so; it is never moved past an effect, nor onto
// fewer paths. A call does what its own effects say: a call that only
// computes moves into the region where its result meets the dispatch that
// raising takes in, which needs the two in one block, and one whose
// effects no pass has found may do anything, and stays. A value that
// moves onto fewer paths may take a linear one, as a call's argument or a
// grade's operand: verify::linearity asks of a linear value that it is used
// at most once on every path, not that every path uses it, and on a path
// that no longer uses it counting releases what it holds, which
// verify::owned checks consumes each reference exactly once on every path.
//
// The copies are bounded by a size policy: each region past the first may
// receive at most kSinkDuplicationLimit ops, so a large match is not copied
// into every case of another. The limit only bounds the code a sink copies;
// a value it keeps in place stays correct where it is. A constant stays
// where it is: the folder hoists constants back, and each would undo the
// other.
//
// Upstream's control-flow sinking moves only what has no memory effect,
// into the one region that uses it, and never copies: a constructor, a
// string builder or a value two regions use stays where it is.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Flow.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;
using namespace idr;

namespace {

constexpr int64_t kSinkDuplicationLimit = 64;

// Whether the user holding `use` folds or canonicalizes against `value`
// once they meet: what feeds() says for a value an op builds, and for a
// match's result, a consumer that case-of-case would move into the match.
bool meets(Value value, OpOperand &use) {
  if (canon::feeds(value, use))
    return true;
  auto result = dyn_cast<OpResult>(value);
  return result && isa<MatchOpInterface>(result.getOwner()) &&
         canon::meetsInSomeRegion(result, use.getOwner());
}

// Whether `value` may run later, in the regions of `match` that use it:
// every path through the match uses it when every region that runs does,
// and an exhaustive match's empty default never runs.
bool movesInto(Operation *value, Operation *match, size_t regions) {
  if (onlyAllocates(value))
    return true;
  auto runs = [](Region &region) { return !region.empty(); };
  if (regions != static_cast<size_t>(llvm::count_if(match->getRegions(), runs)) ||
      performsIO(value))
    return false;
  for (Operation *between = value->getNextNode(); between != match;
       between = between->getNextNode())
    if (!onlyAllocates(between))
      return false;
  return true;
}

// The regions of `match` in which `value` is used.
SmallVector<Region *> usersIn(Operation *value, Operation *match) {
  // One walk of the users. Asking each region whether any user sits in it
  // walks the users again for every case of the match.
  llvm::SmallPtrSet<Region *, 8> hit;
  for (Operation *user : value->getUsers())
    for (Region *region = user->getParentRegion(); region; region = region->getParentRegion())
      if (region->getParentOp() == match) {
        hit.insert(region);
        break;
      }
  SmallVector<Region *> out;
  for (Region &region : match->getRegions())
    if (hit.contains(&region))
      out.push_back(&region);
  return out;
}

// Whether `value` moves into the regions of `match` that use it.
bool sinkable(Operation *value, Operation *match) {
  if (value->getNumResults() == 0 || value->use_empty() ||
      value->hasTrait<OpTrait::ConstantLike>())
    return false;
  if (!llvm::all_of(value->getUsers(), [&](Operation *user) {
        return user != match && match->isAncestor(user);
      }))
    return false;
  size_t regions = usersIn(value, match).size();
  if (!movesInto(value, match, regions))
    return false;
  if (!isa<ConOp, ClosureOp>(value) && !value->hasTrait<ResultCarriesOperand>() &&
      !llvm::any_of(value->getResults(), [&](Value result) {
        return llvm::any_of(result.getUses(), [&](OpOperand &use) { return meets(result, use); });
      }))
    return false;
  // The copies past the first may hold the limit between them: the walk
  // stops once the value holds more ops than that allows.
  int64_t copies = static_cast<int64_t>(regions) - 1;
  if (copies == 0)
    return true;
  int64_t size = 0;
  return !value
              ->walk([&](Operation *) {
                return ++size * copies > kSinkDuplicationLimit ? WalkResult::interrupt()
                                                               : WalkResult::advance();
              })
              .wasInterrupted();
}

// The walk of the ops inside a match, a step at a time: the ranges of the
// blocks still to finish, innermost last. Each step takes one op and adds
// the blocks of its regions, so the walk ends with the ops the match holds.
class Inside {
public:
  explicit Inside(Operation *match) { enter(match); }

  // The next op inside the match, or null once every one was taken.
  Operation *next() {
    while (!ranges.empty() && ranges.back().first == ranges.back().second)
      ranges.pop_back();
    if (ranges.empty())
      return nullptr;
    Operation &op = *ranges.back().first++;
    enter(&op);
    return &op;
  }

private:
  void enter(Operation *op) {
    for (Region &region : op->getRegions())
      for (Block &inner : region)
        ranges.emplace_back(inner.begin(), inner.end());
  }

  SmallVector<std::pair<Block::iterator, Block::iterator>> ranges;
};

// The op nearest before `match` in its block that sinkable() accepts, or
// null. Every such op has a user inside the match, so two searches find it:
// scanning back from the match, which costs the ops before it, and
// collecting the ops of the block that the match's regions use, which costs
// the ops inside it. The rewrite driver revisits a match whenever anything
// inside it changes: a match late in a long block (a `do` block unfolded)
// makes the scan long, a match that nests dozens deep (as case-of-case makes
// them) the walk. The two run a step each in turn, over the ops before the
// match, and the first to finish answers.
Operation *nearestSinkable(Operation *match) {
  Block *block = match->getBlock();
  Inside inside(match);
  llvm::SmallPtrSet<Operation *, 8> used;
  for (Operation *previous = match->getPrevNode(); previous; previous = previous->getPrevNode()) {
    if (sinkable(previous, match))
      return previous;
    Operation *op = inside.next();
    if (!op) {
      // The walk is done: what is left are the used ops before `previous`,
      // latest first.
      SmallVector<Operation *> left;
      for (Operation *def : used)
        if (def->isBeforeInBlock(previous))
          left.push_back(def);
      llvm::sort(left, [](Operation *a, Operation *b) { return b->isBeforeInBlock(a); });
      for (Operation *def : left)
        if (sinkable(def, match))
          return def;
      return nullptr;
    }
    for (Value operand : op->getOperands())
      if (Operation *def = operand.getDefiningOp(); def && def->getBlock() == block)
        used.insert(def);
  }
  return nullptr;
}

// Rooted at a match, as a canonicalization of the match ops is: the
// driver tries it when the match is made or changed, at its seeding of
// every op, and again whenever anything under the match changes, since
// a change requeues its ancestors. From the match, nearestSinkable scans
// every value before it, so each attempt asks the whole question. A
// value that does more than compute leaves the ops between its place and
// the match, and those ops whose own question spans it are tried again.
struct SinkIntoRegions : OpInterfaceRewritePattern<MatchOpInterface> {
  explicit SinkIntoRegions(MLIRContext *context)
      : OpInterfaceRewritePattern(context, PatternBenefit(1)) {
    setDebugName("idr-sink-into-regions");
  }

  LogicalResult matchAndRewrite(MatchOpInterface match, PatternRewriter &rewriter) const final {
    Operation *value = nearestSinkable(match.getOperation());
    if (!value)
      return failure();
    return sink(value, match.getOperation(), rewriter);
  }

private:
  static LogicalResult sink(Operation *value, Operation *match, PatternRewriter &rewriter) {
    // A value that does more than compute stood between each op it moves
    // across and a partner before it. It moves only past ops that compute,
    // which movesInto walked already.
    if (!onlyAllocates(value))
      canon::retryBetween(rewriter, {std::next(value->getIterator()), match->getIterator()});
    for (Region *region : usersIn(value, match)) {
      auto inside = [&](OpOperand &use) {
        return region->isAncestor(use.getOwner()->getParentRegion());
      };
      rewriter.setInsertionPointToStart(&region->front());
      Operation *copy = rewriter.clone(*value);
      rewriter.replaceUsesWithIf(value->getResults(), copy->getResults(), inside);
    }
    rewriter.eraseOp(value);
    return success();
  }
};

} // namespace

namespace idr::canon {

void addSink(RewritePatternSet &results, MLIRContext *context) {
  results.add<SinkIntoRegions>(context);
}

} // namespace idr::canon
