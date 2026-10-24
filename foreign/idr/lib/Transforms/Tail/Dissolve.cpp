// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames: a join point op around a call to frame becomes functions,
// one per join region, each jump to one a tail call of it, so the call's
// block can end a tail of its function. A join region takes no lifetime: the
// function made of it takes the component's, as every function of the
// component does, and its scoped parameters live where the op stated.

#include "idr/Transforms/Tail/Frames.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::tail::frames {

namespace {

// The join region of `join` that `op` lies in, by its number among the
// join regions; none for an op of the body or outside the op.
std::optional<unsigned> joinRegionOf(Operation *join, Operation *op) {
  for (Region *region = op->getParentRegion(); region;) {
    Operation *parent = region->getParentOp();
    if (parent == join) {
      unsigned number = region->getRegionNumber();
      return number == 0 ? std::nullopt : std::optional<unsigned>(number - 1);
    }
    region = parent->getParentRegion();
  }
  return std::nullopt;
}

} // namespace

// A join point op around a call to frame, its continuation already lifted
// so it is in tail position: each join region becomes a function of its
// parameters and what it reads, each jump to it a tail call, and the body
// takes the op's place.
LogicalResult Component::dissolve(FuncOp owner, unsigned row, Operation *join) {
  MLIRContext *ctx = owner.getContext();
  auto points = cast<JoinPointsOpInterface>(join);
  for (Region &region : join->getRegions())
    normalize(&region.front());
  // No join region reads a loan from above the op: each is lent again
  // where the region begins, so its function takes the holder.
  for (Region &region : join->getRegions().drop_front())
    lendAgain(&region.front().front());
  unsigned depth = static_cast<unsigned>(scopeSorts(join->getParentRegion()).size());

  // What each join region reads from above the op, closed over the jumps:
  // a region that jumps to another passes it what it reads, so reads it
  // too. Each value in scope at the op is met once, and those some join
  // region reads are numbered, in scope order; each region's reads are a
  // set of those numbers, a union over finitely many that only grows, so
  // it ends.
  llvm::SmallVector<JumpOp> jumps;
  join->walk([&](JumpOp jump) {
    if (points.getTarget(cast<BlockArgument>(jump.getTarget())))
      jumps.push_back(jump);
  });
  unsigned count = join->getNumRegions() - 1;
  llvm::SmallVector<Value> above;
  // Each value numbered adds its bit to every region's set, so each set is
  // as wide as `above` by construction.
  llvm::SmallVector<llvm::BitVector> reads(count);
  // A join point's own token is upstream's, which no region passes; a
  // reuse token in scope is a value like any other, which one must.
  forEachInScope(join, [&](Value value) {
    if (isa<mlir::TokenType>(value.getType()))
      return;
    llvm::BitVector by(count);
    for (Operation *user : value.getUsers())
      if (std::optional<unsigned> region = joinRegionOf(join, user))
        by.set(*region);
    if (by.none())
      return;
    above.push_back(value);
    for (unsigned region = 0; region < count; ++region)
      reads[region].push_back(by.test(region));
  });
  for (bool grew = true; grew;) {
    grew = false;
    for (JumpOp jump : jumps) {
      // The body passes nothing, its code staying where everything above
      // the op is in scope.
      std::optional<unsigned> from = joinRegionOf(join, jump.getOperation());
      if (!from)
        continue;
      unsigned to = points.getTarget(cast<BlockArgument>(jump.getTarget()))->getRegionNumber() - 1;
      if (reads[to].subsetOf(reads[*from]))
        continue;
      reads[*from] |= reads[to];
      grew = true;
    }
  }

  // The functions, one per join region, before any jump changes, so a
  // jump may name any of them: each takes its parameters, then what it
  // reads from above, then the component's lifetimes, and gives the op's
  // results where the op states they live.
  struct Lifted {
    Region *region;
    FuncOp fn;
    llvm::SmallVector<Value> reads;
    llvm::SmallVector<Value> lifetimes;
  };
  llvm::SmallVector<Value> resultsIn = llvm::map_to_vector(
      join->getResults(), [](Value result) { return lifetimes::statedLifetime(result); });
  llvm::SmallVector<Value> ownLifetimes;
  llvm::append_range(ownLifetimes, lifetimesOf(owner));
  llvm::SmallVector<Lifted> lifted;
  for (unsigned i = 0; i < count; ++i) {
    Region &region = join->getRegion(i + 1);
    llvm::SmallVector<Value> readHere =
        llvm::map_to_vector(reads[i].set_bits(), [&](unsigned at) { return above[at]; });
    llvm::SmallVector<Value> read = withoutLifetimes(readHere);
    llvm::SmallVector<Value> takes(points.getParameters(region));
    llvm::append_range(takes, read);
    llvm::SmallVector<families::Sort> binders = scopeSorts(&region);
    FailureOr<Made> moved =
        makeFunction(owner, "join", takes, join->getResultTypes(), resultsIn, binders);
    if (failed(moved))
      return failure();
    llvm::SmallVector<Value> lifetimesRead = llvm::to_vector(llvm::make_filter_range(
        readHere, [](Value value) { return isa<LifetimeType>(value.getType()); }));
    lifted.push_back({&region, moved->fn, std::move(read), std::move(lifetimesRead)});
    functions.push_back({moved->fn, row});
  }

  // Each jump to one of them a tail call, its terms the region's binders
  // after the scope's own.
  for (JumpOp jump : jumps) {
    Region *target = points.getTarget(cast<BlockArgument>(jump.getTarget()));
    const Lifted &to = lifted[target->getRegionNumber() - 1];
    llvm::SmallVector<Value> args(jump.getArgs());
    llvm::append_range(args, to.reads);
    llvm::append_range(args, ownLifetimes);
    IndexArgsAttr terms = concatArgs(ctx, families::levelArgs(ctx, 0, depth), jump.getTermsAttr());
    rewriter.setInsertionPoint(jump);
    auto call = TailCallOp::create(rewriter, jump.getLoc(), to.fn, terms, args);
    YieldOp::create(rewriter, jump.getLoc(), call.getResults());
    made.push_back(call);
    rewriter.eraseOp(jump);
  }

  // Each join region's code into its function, which changes through its
  // handle; the body in the op's place. A region of a loop Idris did not
  // prove to end begins with idr.may_loop: as a function it repeats through
  // tail calls, a cycle of calls whose divergence the writer of rows reads
  // off its functions' termination, so the function claims none of its
  // owner's proof, and the mark, which only a loop holds, goes.
  for (Lifted &to : lifted) {
    Block &block = to.region->front();
    if (!block.getOps<MayLoopOp>().empty()) {
      to.fn.removeTerminatesAttr();
      for (MayLoopOp mark : llvm::make_early_inc_range(block.getOps<MayLoopOp>()))
        rewriter.eraseOp(mark);
    }
    Block *entry = &to.fn.getBody().front();
    Operation *end = block.getTerminator();
    entry->getOperations().splice(entry->end(), block.getOperations(), block.begin(),
                                  end->getIterator());
    rewriter.setInsertionPointToEnd(entry);
    ReturnOp::create(rewriter, end->getLoc(), end->getOperands());
    rewriter.eraseOp(end);
    Block::BlockArgListType params = points.getParameters(*to.region);
    for (auto [param, arg] : llvm::zip(params, entry->getArguments()))
      rewriter.replaceAllUsesWith(param, arg);
    for (auto [value, arg] :
         llvm::zip(to.reads, entry->getArguments().drop_front(params.size())))
      rewriter.replaceUsesWithIf(value, arg, [&](OpOperand &use) {
        return to.fn->isProperAncestor(use.getOwner());
      });
    if (failed(adoptLifetimes(owner, to.fn, to.lifetimes)))
      return failure();
  }
  Block &body = join->getRegion(0).front();
  Operation *bodyEnd = body.getTerminator();
  llvm::SmallVector<Value> given(bodyEnd->getOperands());
  rewriter.eraseOp(bodyEnd);
  body.eraseArguments(0, body.getNumArguments());
  rewriter.inlineBlockBefore(&body, join);
  rewriter.replaceOp(join, given);
  return success();
}

} // namespace idr::tail::frames
