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
// fewer paths. A call does what its callee's effects say, read through the
// program's table where the canonicalizer has one (CalleePattern): a call
// of a callee that only computes moves into the region where its result
// meets the dispatch that raising takes in, which needs the two in one
// block. Without a table a call may do anything, and stays. A value that
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
  return result && isa<MatchOp, MatchLitOp>(result.getOwner()) &&
         canon::meetsInSomeRegion(result, use.getOwner());
}

// Whether `value` may run later, in the regions of `match` that use it.
bool movesInto(Operation *value, Operation *match, size_t regions,
               const CalleeEffects *callees) {
  if (onlyAllocates(value, callees))
    return true;
  if (regions != match->getNumRegions() || performsIO(value, callees))
    return false;
  for (Operation *between = value->getNextNode(); between != match;
       between = between->getNextNode())
    if (!onlyAllocates(between, callees))
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
bool sinkable(Operation *value, Operation *match, const CalleeEffects *callees) {
  if (value->getNumResults() == 0 || value->use_empty() ||
      value->hasTrait<OpTrait::ConstantLike>())
    return false;
  if (!llvm::all_of(value->getUsers(), [&](Operation *user) {
        return user != match && match->isAncestor(user);
      }))
    return false;
  size_t regions = usersIn(value, match).size();
  if (!movesInto(value, match, regions, callees))
    return false;
  if (!isa<ConOp, ClosureOp>(value) && !value->hasTrait<ResultCarriesOperand>() &&
      !llvm::any_of(value->getResults(), [&](Value result) {
        return llvm::any_of(result.getUses(), [&](OpOperand &use) { return meets(result, use); });
      }))
    return false;
  int64_t size = 0;
  value->walk([&](Operation *) { ++size; });
  return (static_cast<int64_t>(regions) - 1) * size <= kSinkDuplicationLimit;
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
Operation *nearestSinkable(Operation *match, const CalleeEffects *callees) {
  Block *block = match->getBlock();
  Inside inside(match);
  llvm::SmallPtrSet<Operation *, 8> used;
  for (Operation *previous = match->getPrevNode(); previous; previous = previous->getPrevNode()) {
    if (sinkable(previous, match, callees))
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
        if (sinkable(def, match, callees))
          return def;
      return nullptr;
    }
    for (Value operand : op->getOperands())
      if (Operation *def = operand.getDefiningOp(); def && def->getBlock() == block)
        used.insert(def);
  }
  return nullptr;
}

// The match `value` would move into: the op of its block whose regions
// hold every user of it, when that is a match after it; null otherwise.
Operation *holdingMatch(Operation *value) {
  Block *block = value->getBlock();
  Operation *match = nullptr;
  for (Operation *user : value->getUsers()) {
    Operation *at = block ? block->findAncestorOpInBlock(*user) : nullptr;
    if (!at || (match && at != match))
      return nullptr;
    match = at;
  }
  if (!isa_and_nonnull<MatchOp, MatchLitOp>(match) || !value->isBeforeInBlock(match))
    return nullptr;
  return match;
}

// Tried at every op, so that each change the driver reports reaches it:
// at a match, whose regions changed or were filled, the nearest value
// before it that moves in; at any other op, which was made or changed, the
// match its users are in. A value that does more than compute leaves the
// ops between its place and the match, and those ops whose own question
// spans it are tried again.
struct SinkIntoRegions : canon::CalleePattern {
  SinkIntoRegions(MLIRContext *context, const CalleeEffects *callees)
      : CalleePattern(MatchAnyOpTypeTag(), "idr-sink-into-regions", context, callees) {}

  std::unique_ptr<CalleePattern> withCallees(const CalleeEffects *table) const final {
    return std::make_unique<SinkIntoRegions>(getContext(), table);
  }

  LogicalResult matchAndRewrite(Operation *op, PatternRewriter &rewriter) const final {
    if (isa<MatchOp, MatchLitOp>(op)) {
      if (Operation *value = nearestSinkable(op, callees))
        return sink(value, op, rewriter);
    }
    Operation *match = holdingMatch(op);
    if (!match || !sinkable(op, match, callees))
      return failure();
    return sink(op, match, rewriter);
  }

private:
  LogicalResult sink(Operation *value, Operation *match, PatternRewriter &rewriter) const {
    // A value that does more than compute stood between each op it moves
    // across and a partner before it. It moves only past ops that compute,
    // which movesInto walked already.
    if (!onlyAllocates(value, callees))
      retryBetween(rewriter, {std::next(value->getIterator()), match->getIterator()});
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
  results.add<SinkIntoRegions>(context, /*callees=*/nullptr);
}

} // namespace idr::canon
