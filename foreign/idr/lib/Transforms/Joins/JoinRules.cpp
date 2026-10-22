// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The skeleton rules of the join points: a result no op uses, an idr.loop
// whose regions never repeat, a join region no jump reaches, one reached
// by the body's own end alone, and a parameter its region never reads.
// Each keeps the lifetimes the op states one per scoped value it still
// makes: a value that goes takes its entry of `outers` with it.

#include "idr/IR/Control/Control.h"
#include "idr/IR/Control/Stated.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ops/Rules.h"
#include "idr/Transforms/EGraph.h"
#include "idr/Transforms/Joins/Rules.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr::control;
using namespace idr::egraph;

namespace idr {

namespace {

// Drops from the lifetimes `op` states those of the scoped values in
// `bound`, which one of its regions binds, before they go: the scoped
// results' entries come first, then what each region binds, in order.
template <typename Group>
void dropBindings(RewriterBase &rewriter, Group op, ValueRange bound) {
  unsigned results = scopedResultCount(op);
  SmallVector<unsigned> entries;
  for (Value value : bound)
    if (scoped(value))
      entries.push_back(results + *op.getBindingEntry(value));
  if (entries.empty())
    return;
  rewriter.modifyOpInPlace(op, [&] {
    for (unsigned at : llvm::reverse(entries))
      op.getOutersMutable().erase(at);
  });
}

// The join regions of `op` some jump reaches, by position: those whose
// token some region of `op` uses. A region inlined at its one jump is
// empty, and begins with no token.
template <typename Group>
llvm::BitVector reachedTargets(Group op) {
  unsigned targets = static_cast<unsigned>(op.getJoinRegions().size());
  llvm::BitVector reached(targets, false);
  for (Region &region : op->getRegions()) {
    if (region.empty())
      continue;
    Block::BlockArgListType tokens = op.getTokens(region);
    for (unsigned i = 0, e = static_cast<unsigned>(tokens.size()); i < e; ++i)
      if (!tokens[i].use_empty())
        reached.set(i);
  }
  return reached;
}

// The join regions of `op` no jump reaches, by position.
template <typename Group>
SmallVector<unsigned, 4> unreachedTargets(Group op) {
  llvm::BitVector reached = reachedTargets(op);
  SmallVector<unsigned, 4> found;
  for (unsigned i = 0, e = static_cast<unsigned>(reached.size()); i < e; ++i)
    if (!reached.test(i))
      found.push_back(i);
  return found;
}

// Each join region at a position of `chosen` that no jump reaches still
// goes with its token and its binders; a group left with none is its
// body, whose yield gives the results.
template <typename Group>
void unreached(RewriterBase &rewriter, Group op, ArrayRef<unsigned> chosen) {
  unsigned targets = static_cast<unsigned>(op.getJoinRegions().size());
  llvm::BitVector reached = reachedTargets(op);
  llvm::BitVector dead(targets, false);
  for (unsigned at : chosen)
    if (at < targets && !reached.test(at))
      dead.set(at);
  if (dead.none())
    return;
  if (dead.all()) {
    Block &body = op.getBody().front();
    auto yield = dyn_cast<YieldOp>(body.getTerminator());
    body.eraseArguments(0, body.getNumArguments());
    rewriter.inlineBlockBefore(&body, op);
    if (yield) {
      rewriter.replaceOp(op, yield.getResults());
      rewriter.eraseOp(yield);
      return;
    }
    // The body jumps out or never ends: nothing reaches what follows.
    eraseAfter(rewriter, op);
    rewriter.eraseOp(op);
    return;
  }
  SmallVector<Attribute> binders;
  for (unsigned i = 0; i < targets; ++i)
    if (!dead.test(i))
      binders.push_back(op.getBinders()[i]);
  // A region that goes takes the lifetimes of what it binds with it, the
  // last first, so each entry left keeps its place until its own turn.
  for (unsigned i = targets; i-- > 0;)
    if (dead.test(i) && !op.getJoinRegions()[i].empty())
      dropBindings(rewriter, op, op.getJoinRegions()[i].getArguments());
  for (Region &region : op->getRegions()) {
    if (region.empty())
      continue;
    Block &entry = region.front();
    unsigned leading = static_cast<unsigned>(op.getTokens(region).size());
    for (unsigned i = leading; i-- > 0;)
      if (dead.test(i))
        entry.eraseArgument(i);
  }
  // A region inlined at its one jump is empty already, its lifetimes gone
  // with its parameters.
  for (unsigned i = targets; i-- > 0;)
    if (dead.test(i) && !op.getJoinRegions()[i].empty())
      rewriter.eraseBlock(&op.getJoinRegions()[i].front());
  rewriter.setInsertionPoint(op);
  OperationState state(op.getLoc(), op->getName().getStringRef(), op->getOperands(),
                       op->getResultTypes());
  state.template getOrAddProperties<typename Group::Properties>().binders =
      rewriter.getArrayAttr(binders);
  state.addRegion();
  for (unsigned i = 0; i < targets; ++i)
    if (!dead.test(i))
      state.addRegion();
  Operation *fresh = rewriter.create(state);
  rewriter.inlineRegionBefore(op.getBody(), fresh->getRegion(0), fresh->getRegion(0).end());
  unsigned next = 1;
  for (unsigned i = 0; i < targets; ++i)
    if (!dead.test(i)) {
      Region &into = fresh->getRegion(next++);
      rewriter.inlineRegionBefore(op.getJoinRegions()[i], into, into.end());
    }
  rewriter.replaceOp(op, fresh->getResults());
}

// The join regions of `op` with a parameter no op of the region reads, by
// position.
template <typename Group>
SmallVector<unsigned, 4> unreadTargets(Group op) {
  SmallVector<unsigned, 4> found;
  MutableArrayRef<Region> regions = op.getJoinRegions();
  for (unsigned at = 0, e = static_cast<unsigned>(regions.size()); at < e; ++at)
    if (!regions[at].empty() &&
        llvm::any_of(op.getParameters(regions[at]),
                     [](BlockArgument parameter) { return parameter.use_empty(); }))
      found.push_back(at);
  return found;
}

// In each join region at a position of `chosen`, a parameter no op of the
// region uses goes, with every jump's argument for it and the lifetime its
// op states for it.
template <typename Group>
void unread(RewriterBase &rewriter, Group op, ArrayRef<unsigned> chosen) {
  MutableArrayRef<Region> regions = op.getJoinRegions();
  for (unsigned at : chosen) {
    if (at >= regions.size() || regions[at].empty())
      continue;
    Region &region = regions[at];
    Block::BlockArgListType parameters = op.getParameters(region);
    unsigned leading = static_cast<unsigned>(op.getTokens(region).size());
    for (unsigned i = static_cast<unsigned>(parameters.size()); i-- > 0;) {
      if (!parameters[i].use_empty())
        continue;
      unsigned target = region.getRegionNumber() - 1;
      for (Region &from : op->getRegions()) {
        Block::BlockArgListType tokens = op.getTokens(from);
        if (target >= tokens.size())
          continue;
        for (Operation *user : llvm::make_early_inc_range(tokens[target].getUsers()))
          rewriter.modifyOpInPlace(user, [&] { cast<JumpOp>(user).getArgsMutable().erase(i); });
      }
      dropBindings(rewriter, op, parameters.slice(i, 1));
      region.front().eraseArgument(leading + i);
    }
  }
}

// The jump that ends `op`'s body, when it is the one jump to its target
// and the target binds no index variable: the region runs in its place.
JumpOp singleJump(JoinOp op) {
  auto jump = dyn_cast<JumpOp>(op.getBody().front().getTerminator());
  if (!jump || !jump.getTarget().hasOneUse())
    return JumpOp();
  Region *target = op.getTarget(cast<BlockArgument>(jump.getTarget()));
  return target && op.getBoundSorts(*target).empty() ? jump : JumpOp();
}

// The position of the join region a jump of an idr.join's body goes to:
// its token is the body's argument at that position.
unsigned targetPosition(JumpOp jump) {
  return cast<BlockArgument>(jump.getTarget()).getArgNumber();
}

} // namespace

// A result of a join point's op no op uses goes, with every yield's operand.
std::optional<Edit> egraph::DeadJoinResults::decide(JoinPointsOpInterface op,
                                                    const OperandFacts &) {
  return choose(unusedResults(op));
}

void egraph::DeadJoinResults::rewrite(JoinPointsOpInterface op, const Rewrite &chosen,
                                      RewriterBase &rewriter) {
  dropUnused(rewriter, op.getOperation(), chosen.chosen);
}

// An idr.loop whose join regions never jump to its own op repeats nothing:
// it is an idr.join, its join regions' tokens dropped. No token is scoped,
// so it states the same lifetimes in the same order.
std::optional<Edit> egraph::LoopToJoin::decide(LoopOp op, const OperandFacts &) {
  if (llvm::any_of(op.getJoinRegions(), [&](Region &region) {
        return llvm::any_of(op.getTokens(region),
                            [](BlockArgument token) { return !token.use_empty(); });
      }))
    return std::nullopt;
  return Edit(Rewrite{});
}

void egraph::LoopToJoin::rewrite(LoopOp op, const Rewrite &, RewriterBase &rewriter) {
  rewriter.setInsertionPoint(op);
  OperationState state(op.getLoc(), JoinOp::getOperationName(), op->getOperands(),
                       op->getResultTypes());
  state.getOrAddProperties<JoinOp::Properties>().binders = op.getBinders();
  for (unsigned i = 0, e = op->getNumRegions(); i < e; ++i)
    state.addRegion();
  Operation *join = rewriter.create(state);
  for (auto [from, into] : llvm::zip_equal(op->getRegions(), join->getRegions()))
    rewriter.inlineRegionBefore(from, into, into.end());
  unsigned targets = static_cast<unsigned>(op.getJoinRegions().size());
  for (Region &region : llvm::drop_begin(join->getRegions()))
    region.front().eraseArguments(0, targets);
  rewriter.replaceOp(op, join->getResults());
}

// A join region no jump reaches goes with its token and its binders; a
// group left with none is its body.
std::optional<Edit> egraph::DeadJoinRegions::decide(JoinOp op, const OperandFacts &) {
  return choose(unreachedTargets(op));
}

void egraph::DeadJoinRegions::rewrite(JoinOp op, const Rewrite &chosen, RewriterBase &rewriter) {
  unreached(rewriter, op, chosen.chosen);
}

std::optional<Edit> egraph::DeadLoopRegions::decide(LoopOp op, const OperandFacts &) {
  return choose(unreachedTargets(op));
}

void egraph::DeadLoopRegions::rewrite(LoopOp op, const Rewrite &chosen, RewriterBase &rewriter) {
  unreached(rewriter, op, chosen.chosen);
}

// A join region of an idr.join reached by one jump, the body's own end,
// runs there: its block takes the jump's place, the jump's arguments its
// parameters, whose lifetimes go with them, and the region, now empty,
// goes. The rule chooses the region by its position.
std::optional<Edit> egraph::InlineSingleJump::decide(JoinOp op, const OperandFacts &) {
  JumpOp jump = singleJump(op);
  if (!jump)
    return std::nullopt;
  return Edit(Rewrite{{targetPosition(jump)}});
}

void egraph::InlineSingleJump::rewrite(JoinOp op, const Rewrite &chosen,
                                       RewriterBase &rewriter) {
  JumpOp jump = singleJump(op);
  if (!jump || targetPosition(jump) != chosen.chosen.front())
    return;
  unsigned at = targetPosition(jump);
  Region *target = op.getTarget(cast<BlockArgument>(jump.getTarget()));
  SmallVector<Value> args(jump.getArgs());
  Block &from = target->front();
  dropBindings(rewriter, op, from.getArguments());
  rewriter.eraseOp(jump);
  rewriter.mergeBlocks(&from, &op.getBody().front(), args);
  unreached(rewriter, op, {at});
}

// A parameter its join region never reads goes, with every jump's argument
// for it; the rule chooses the regions that have one.
std::optional<Edit> egraph::DeadJoinParameters::decide(JoinOp op, const OperandFacts &) {
  return choose(unreadTargets(op));
}

void egraph::DeadJoinParameters::rewrite(JoinOp op, const Rewrite &chosen,
                                         RewriterBase &rewriter) {
  unread(rewriter, op, chosen.chosen);
}

std::optional<Edit> egraph::DeadLoopParameters::decide(LoopOp op, const OperandFacts &) {
  return choose(unreadTargets(op));
}

void egraph::DeadLoopParameters::rewrite(LoopOp op, const Rewrite &chosen,
                                         RewriterBase &rewriter) {
  unread(rewriter, op, chosen.chosen);
}

} // namespace idr
