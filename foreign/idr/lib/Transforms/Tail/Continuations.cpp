// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames' first step: continuations become functions. Each call to
// frame must end its block in a tail of its function, so every region op
// around it whose results something after it reads gives its continuation
// to a function of its own (a lifted continuation), which each region of
// the op tail-calls; a join point around it becomes functions too
// (Dissolve.cpp); a lifetime's region around it splits (Split.cpp); and
// the rest of the call's block becomes a function its call runs into,
// tail-calling it with what the rest reads (Outline.cpp). Each step moves
// code, never copies it, and makes a function of the component, read in
// turn, so it ends: the code it moves only shrinks.
//
// A region op made again with other results states its new results'
// lifetimes and keeps those of what its regions bind.

#include "idr/Transforms/Tail/Frames.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::tail::frames {

namespace {

// What the package of the lifetime `op`'s region binds holds, when frames
// split that region: an opener's or an unpack's (RunsOnce), whose region's
// first argument is its lifetime, if that lifetime may be per level. None
// for any other op.
std::optional<Packed> perLevel(Operation *op) {
  if (!op->hasTrait<RunsOnce>())
    return std::nullopt;
  return lifetimes::packedOf(op->getRegion(0).front().getArgument(0));
}

// The internal error for `op`, a region op around `site`, a call to frame,
// which frames cannot split. Which pass promised that no such op is there
// is read off the op, so a report goes to it: a lifetime's opener, or the
// unpack frames made of one, is the decide step's; a loan is borrows'.
// Any other region op is one no pass before frames keeps such a call out
// of.
LogicalResult unsplittable(CallOp site, Operation *op) {
  if (op->hasTrait<RunsOnceGivingBack>())
    return site.emitOpError(
               "internal error: an invariant of idr-rc-borrows is broken (idr-frames): no loan "
               "wraps a call on its function's own cycle, directly or in a join point, but ")
           << op->getName() << " wraps this one";
  if (op->hasTrait<RunsOnce>())
    return site.emitOpError(
               "internal error: an invariant of idr-lifetimes is broken (idr-frames): a "
               "lifetime spanning a call on frames is per level and opens directly around the "
               "call, never around a match or another op that holds it, but ")
           << op->getName() << " is around this one";
  return site.emitOpError("internal error: idr-frames: a call on its function's cycle inside ")
         << op->getName()
         << ", whose region frames do not split and no pass before them keeps such a call out of";
}

} // namespace

// `call`, right after `rejoin` and taking its results, moved into each of
// its regions that rejoins it: each tail-calls the continuation with what
// it gives, and the op gives the continuation's results, each scoped one
// where the call says it lives, so it is in tail position once its block
// gives them.
void Component::sinkInto(Operation *rejoin, CallOp call) {
  llvm::SmallVector<Operation *> ends;
  for (Region &region : rejoin->getRegions()) {
    if (region.empty())
      continue;
    Operation *end = region.front().getTerminator();
    if (isa<RegionBranchTerminatorOpInterface>(end) &&
        end->getNumOperands() == rejoin->getNumResults())
      ends.push_back(end);
  }
  for (Operation *end : ends) {
    rewriter.setInsertionPoint(end);
    IRMapping map;
    for (auto [result, given] : llvm::zip_equal(rejoin->getResults(), end->getOperands()))
      map.map(result, given);
    auto copy = cast<CallOp>(rewriter.clone(*call, map));
    rewriter.modifyOpInPlace(end, [&] { end->setOperands(copy.getResults()); });
    made.push_back(copy);
  }
  llvm::SmallVector<Value> outers;
  for (OpResult result : call->getResults())
    if (freedBy(result.getType(), Release::Scoped))
      outers.push_back(call.getStatedLifetime(result));
  Operation *remade = remakeGiving(rewriter, rejoin, call.getResultTypes(), outers);
  rewriter.replaceAllUsesWith(call.getResults(), remade->getResults());
  llvm::erase(made, call);
  rewriter.eraseOp(call);
  rewriter.eraseOp(rejoin);
}

// The changes of grade after each region op of the tail spine from `root`
// moved into the op's regions, before each region's end: every region op
// a tail runs through then gives what its function gives, type for type,
// each scoped result where the change of grade stated it, so a
// continuation made of the code after one gives it too.
void Component::normalize(Block *root) {
  llvm::SmallVector<Block *, 8> spine{root};
  while (!spine.empty()) {
    Block *block = spine.pop_back_val();
    Operation *source = tailSource(*block);
    if (!source || !source->hasTrait<OpTrait::PropagateControlFlowBreak>())
      continue;
    llvm::SmallVector<Operation *> ends;
    for (Region &region : source->getRegions()) {
      if (region.empty())
        continue;
      Operation *end = region.front().getTerminator();
      if (isa<RegionBranchTerminatorOpInterface>(end) &&
          end->getNumOperands() == source->getNumResults())
        ends.push_back(end);
    }
    llvm::SmallVector<Type> types(source->getResultTypes());
    llvm::SmallVector<Value> livesIn = llvm::map_to_vector(
        source->getResults(), [](Value result) { return lifetimes::statedLifetime(result); });
    llvm::SmallVector<Operation *> regrades;
    for (Operation *op = source->getNextNode(); !op->hasTrait<OpTrait::IsTerminator>();
         op = op->getNextNode())
      regrades.push_back(op);
    for (Operation *regrade : regrades) {
      unsigned at = cast<OpResult>(regrade->getOperand(0)).getResultNumber();
      for (Operation *end : ends) {
        rewriter.setInsertionPoint(end);
        Operation *copy = rewriter.clone(*regrade);
        copy->setOperand(0, end->getOperand(at));
        rewriter.modifyOpInPlace(end, [&] { end->setOperand(at, copy->getResult(0)); });
      }
      types[at] = regrade->getResult(0).getType();
      livesIn[at] = lifetimes::statedLifetime(regrade->getResult(0));
      rewriter.replaceAllUsesWith(regrade->getResult(0), source->getResult(at));
      rewriter.eraseOp(regrade);
    }
    if (!regrades.empty()) {
      llvm::SmallVector<Value> outers;
      for (auto [type, lifetime] : llvm::zip_equal(types, livesIn))
        if (freedBy(type, Release::Scoped))
          outers.push_back(lifetime);
      Operation *remade = remakeGiving(rewriter, source, types, outers);
      rewriter.replaceAllUsesWith(source->getResults(), remade->getResults());
      rewriter.eraseOp(source);
      source = remade;
    }
    for (Operation *end : ends)
      spine.push_back(end->getBlock());
  }
}

LogicalResult Component::restructure(FuncOp fn, unsigned row) {
  for (;;) {
    // A join point op around a call to frame, outermost first, and the
    // first such call in it.
    Operation *join = nullptr;
    CallOp held;
    fn.walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (!op->hasTrait<OpTrait::TokenProducerTrait>())
        return WalkResult::advance();
      op->walk([&](CallOp call) {
        if (!frames(call))
          return WalkResult::advance();
        held = call;
        return WalkResult::interrupt();
      });
      if (!held)
        return WalkResult::skip();
      join = op;
      return WalkResult::interrupt();
    });
    if (!join)
      break;
    // It is dissolved once in tail position, which only ops a break
    // crosses let it reach: under any other, lifting its continuation
    // would lift an empty one again and again.
    for (Operation *op = join->getParentOp(); op != fn.getOperation(); op = op->getParentOp())
      if (!op->hasTrait<OpTrait::PropagateControlFlowBreak>())
        return unsplittable(held, op);
    normalize(&fn.getBody().front());
    if (!inTailPosition(join)) {
      FailureOr<CallOp> continuation =
          outline(fn, row, join->getNextNode(), join->getResults(), "k");
      if (failed(continuation))
        return failure();
      sinkInto(join, *continuation);
      // The op was made again: it is found afresh.
      continue;
    }
    if (failed(dissolve(fn, row, join)))
      return failure();
  }
  normalize(&fn.getBody().front());

  // Each call to frame, in program order; one an earlier one's change moved
  // into a function of its own is that function's.
  llvm::SmallVector<CallOp> sites;
  fn.walk<WalkOrder::PreOrder>([&](CallOp call) {
    if (frames(call))
      sites.push_back(call);
  });
  for (CallOp site : sites) {
    if (site->getParentOfType<FuncOp>() != fn)
      continue;
    // The region ops around the call, outermost first: each a break may
    // cross whose results something after it reads gives its continuation
    // to a function, until the call's block ends a tail. Each such change
    // remakes the ops around, so they are read again after it. Any other
    // op may only be the one directly around the call.
    for (;;) {
      llvm::SmallVector<Operation *> around;
      for (Operation *op = site->getParentOp(); op != fn.getOperation(); op = op->getParentOp())
        around.push_back(op);
      Operation *lift = nullptr;
      for (Operation *op : llvm::reverse(around)) {
        if (op->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
          if (inTailPosition(op))
            continue;
          lift = op;
          break;
        }
        if (op != site->getParentOp())
          return unsplittable(site, op);
      }
      if (!lift)
        break;
      FailureOr<CallOp> continuation =
          outline(fn, row, lift->getNextNode(), lift->getResults(), "k");
      if (failed(continuation))
        return failure();
      sinkInto(lift, *continuation);
      normalize(&fn.getBody().front());
    }
    // The rest of the call's block runs after it: in a per-level
    // lifetime's region, which ends before the call, reopened by the rest.
    Operation *parent = site->getParentOp();
    if (parent != fn.getOperation() && !parent->hasTrait<OpTrait::PropagateControlFlowBreak>()) {
      std::optional<Packed> packed = perLevel(parent);
      if (!packed)
        return unsplittable(site, parent);
      if (failed(split(fn, row, site, parent, *packed)))
        return failure();
      continue;
    }
    FailureOr<CallOp> rest = outline(fn, row, site->getNextNode(), site->getResults(), "rest");
    if (failed(rest))
      return failure();
    framed.push_back({site, *rest});
  }
  return success();
}

} // namespace idr::tail::frames
