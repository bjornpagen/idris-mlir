// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames: a join point op around a call to frame becomes functions,
// one per join region, each jump to one a tail call of it, so the call's
// block can end a tail of its function.

#include "idr/Transforms/Tail/Frames.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::tail::frames {

// A join point op around a call to frame, its continuation already lifted
// so it is in tail position: each join region becomes a function of its
// parameters and what it reads, each jump to it a tail call, and the body
// takes the op's place.
LogicalResult Component::dissolve(FuncOp owner, unsigned row, Operation *join) {
  MLIRContext *ctx = owner.getContext();
  auto points = cast<JoinPointsOpInterface>(join);
  for (Region &region : join->getRegions())
    normalize(&region.front());
  unsigned depth = static_cast<unsigned>(scopeSorts(join->getParentRegion()).size());

  // What each join region reads from above the op, closed over the jumps:
  // a region that jumps to another passes it what it reads, so reads it
  // too. A union over finitely many values that only grows, so it ends.
  llvm::SmallVector<JumpOp> jumps;
  join->walk([&](JumpOp jump) {
    if (points.getTarget(cast<BlockArgument>(jump.getTarget())))
      jumps.push_back(jump);
  });
  unsigned count = join->getNumRegions() - 1;
  llvm::SmallVector<llvm::SetVector<Value>> reads(count);
  for (unsigned i = 0; i < count; ++i) {
    Region &region = join->getRegion(i + 1);
    region.walk([&](Operation *op) {
      for (Value operand : op->getOperands())
        if (!region.isAncestor(operand.getParentRegion()) && !isa<TokenType>(operand.getType()))
          reads[i].insert(operand);
    });
  }
  for (bool grew = true; grew;) {
    grew = false;
    for (JumpOp jump : jumps) {
      // The region of the op the jump lies in; the body passes nothing,
      // its code staying where everything above the op is in scope.
      Region *home = jump->getParentRegion();
      while (home->getParentOp() != join)
        home = home->getParentOp()->getParentRegion();
      unsigned from = home->getRegionNumber();
      if (from == 0)
        continue;
      unsigned to = points.getTarget(cast<BlockArgument>(jump.getTarget()))->getRegionNumber() - 1;
      for (Value value : reads[to])
        grew |= reads[from - 1].insert(value);
    }
  }

  // The functions, one per join region, before any jump changes, so a
  // jump may name any of them.
  struct Lifted {
    Region *region;
    FuncOp fn;
    llvm::SmallVector<Value> reads;
  };
  llvm::SmallVector<Lifted> lifted;
  for (unsigned i = 0; i < count; ++i) {
    Region &region = join->getRegion(i + 1);
    llvm::SmallVector<Type> inputs(points.getParameters(region).getTypes());
    for (Value value : reads[i])
      inputs.push_back(value.getType());
    llvm::SmallVector<families::Sort> binders = scopeSorts(&region);
    FuncOp fn = makeFunction(owner, "join", FunctionType::get(ctx, inputs, join->getResultTypes()),
                             binders);
    lifted.push_back({&region, fn, llvm::to_vector(reads[i])});
    functions.push_back({fn, row});
  }

  // Each jump to one of them a tail call, its terms the region's binders
  // after the scope's own.
  for (JumpOp jump : jumps) {
    Region *target = points.getTarget(cast<BlockArgument>(jump.getTarget()));
    const Lifted &to = lifted[target->getRegionNumber() - 1];
    llvm::SmallVector<Value> args(jump.getArgs());
    llvm::append_range(args, to.reads);
    IndexArgsAttr terms = concatArgs(ctx, families::levelArgs(ctx, 0, depth), jump.getTermsAttr());
    rewriter.setInsertionPoint(jump);
    auto call = CallOp::create(rewriter, jump.getLoc(), to.fn, terms, args, TailKind::tail);
    YieldOp::create(rewriter, jump.getLoc(), call.getResults());
    made.push_back(call);
    rewriter.eraseOp(jump);
  }

  // Each join region's code into its function; the body in the op's place.
  for (const Lifted &to : lifted) {
    Block &block = to.region->front();
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
         llvm::zip_equal(to.reads, entry->getArguments().drop_front(params.size())))
      rewriter.replaceUsesWithIf(value, arg, [&](OpOperand &use) {
        return to.fn->isProperAncestor(use.getOwner());
      });
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
