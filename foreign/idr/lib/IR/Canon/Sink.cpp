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
// fewer paths. A call stays where it is: what it may do is its callee's,
// which only a symbol table reaches, so to the effects read here it may do
// anything (idr-optimize's pure-calls step drops and merges the calls that
// only compute).
//
// The copies are bounded: each region past the first may receive at most
// kSinkBudget ops, so a large match is not copied into every case of
// another. A constant stays where it is: the folder hoists constants back,
// and each would undo the other.
//
// Upstream's control-flow sinking moves only what has no memory effect,
// into the one region that uses it, and never copies: a constructor, a
// string builder or a value two regions use stays where it is.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"

#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

constexpr int64_t kSinkBudget = 64;

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
bool movesInto(Operation *value, Operation *match, size_t regions) {
  if (onlyAllocates(value))
    return true;
  if (regions != match->getNumRegions() || performsIO(value))
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
  for (Operation *user : value->getUsers()) {
    Region *region = user->getParentRegion();
    while (region && region->getParentOp() != match)
      region = region->getParentRegion();
    if (region)
      hit.insert(region);
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
  int64_t size = 0;
  value->walk([&](Operation *) { ++size; });
  return (static_cast<int64_t>(regions) - 1) * size <= kSinkBudget;
}

// The op nearest before `match` in its block that sinkable() accepts, or
// null. Every such op has a user inside the match, so two searches find it:
// scanning back from the match, which costs the ops before it, and
// collecting the ops of the block that the match's regions use, which costs
// the ops inside it. The rewrite driver revisits a match whenever anything
// inside it changes: a match late in a long block (a `do` block unfolded)
// makes the scan long, a match that nests dozens deep (as case-of-case makes
// them) the walk. The two run a step each in turn, and the first to finish
// answers.
Operation *nearestSinkable(Operation *match) {
  Block *block = match->getBlock();
  Operation *scanned = match;
  SmallVector<std::pair<Block::iterator, Block::iterator>> walk;
  for (Region &region : match->getRegions())
    for (Block &inner : region)
      walk.emplace_back(inner.begin(), inner.end());
  llvm::SmallPtrSet<Operation *, 8> used;
  while (true) {
    Operation *previous = scanned->getPrevNode();
    if (!previous)
      return nullptr;
    if (sinkable(previous, match))
      return previous;
    scanned = previous;

    while (!walk.empty() && walk.back().first == walk.back().second)
      walk.pop_back();
    if (walk.empty())
      break;
    Operation &op = *walk.back().first++;
    for (Value operand : op.getOperands())
      if (Operation *def = operand.getDefiningOp(); def && def->getBlock() == block)
        used.insert(def);
    for (Region &region : op.getRegions())
      for (Block &inner : region)
        walk.emplace_back(inner.begin(), inner.end());
  }
  // The walk is done: what is left are the used ops before the last one
  // scanned, latest first.
  SmallVector<Operation *> left;
  for (Operation *def : used)
    if (def->isBeforeInBlock(scanned))
      left.push_back(def);
  llvm::sort(left, [](Operation *a, Operation *b) { return b->isBeforeInBlock(a); });
  for (Operation *def : left)
    if (sinkable(def, match))
      return def;
  return nullptr;
}

template <typename Match>
struct SinkIntoRegions : OpRewritePattern<Match> {
  explicit SinkIntoRegions(MLIRContext *context) : OpRewritePattern<Match>(context) {
    this->setDebugName("idr-sink-into-regions");
  }
  LogicalResult matchAndRewrite(Match op, PatternRewriter &rewriter) const final {
    Operation *value = nearestSinkable(op);
    if (!value)
      return failure();
    for (Region *region : usersIn(value, op)) {
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

template <typename Match>
void addSink(RewritePatternSet &results, MLIRContext *context) {
  results.add<SinkIntoRegions<Match>>(context);
}

template void addSink<MatchOp>(RewritePatternSet &, MLIRContext *);
template void addSink<MatchLitOp>(RewritePatternSet &, MLIRContext *);

} // namespace idr::canon
