// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-frames: the component's lifetimes. Every function a component runs
// on its stack takes them, the same kinds in the same order, after its
// values; a scoped value lives in one of them, named by its place among
// them, so a function the pass makes reads its owner's lifetimes as its own
// at the same places, and an op made again restates where what it gives
// lives.

#include "idr/Transforms/Tail/Frames.h"

#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Support/Remake.h"

#include "mlir/IR/IRMapping.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::tail::frames {

llvm::SmallVector<BlockArgument> lifetimesOf(FuncOp fn) {
  llvm::SmallVector<BlockArgument> lifetimes;
  for (BlockArgument param : fn.getBody().front().getArguments())
    if (isa<LifetimeType>(param.getType()))
      lifetimes.push_back(param);
  return lifetimes;
}

std::optional<unsigned> placeOf(Value lifetime, FuncOp fn) {
  auto param = dyn_cast<BlockArgument>(lifetimes::extentOf(lifetime));
  Block &entry = fn.getBody().front();
  if (!param || param.getOwner() != &entry || !isa<LifetimeType>(param.getType()))
    return std::nullopt;
  return static_cast<unsigned>(
      llvm::count_if(entry.getArguments().take_front(param.getArgNumber()),
                     [](BlockArgument before) { return isa<LifetimeType>(before.getType()); }));
}

// A function's signature names a lifetime parameter for each scoped result,
// which its verifier holds, so each has its place.
Row givenRow(FuncOp fn) {
  Row row;
  llvm::append_range(row.types, fn.getResultTypes());
  if (LivesInAttr lives = fn.getLivesInAttr())
    for (const LivesIn &result : lives.getResults())
      row.livesIn.push_back(*placeOf(fn.getBody().front().getArgument(result.lifetime), fn));
  return row;
}

Value givenIn(Operation *terminator, unsigned index) {
  if (isa<ReturnOp>(terminator)) {
    auto fn = terminator->getParentOfType<FuncOp>();
    LivesInAttr lives = fn.getLivesInAttr();
    std::optional<std::uint32_t> in = lives ? lives.lifetimeOfResult(index) : std::nullopt;
    return in ? Value(fn.getBody().front().getArgument(*in)) : Value();
  }
  return lifetimes::statedLifetime(terminator->getParentOp()->getResult(index));
}

Operation *remakeGiving(RewriterBase &rewriter, Operation *op, TypeRange results,
                        ValueRange resultOuters) {
  auto states = dyn_cast<StatesOutersOpInterface>(op);
  llvm::SmallVector<Value> outers(resultOuters);
  if (states) {
    OperandRange stated = states.getOutersMutable();
    auto scoped = static_cast<unsigned>(llvm::count_if(op->getResults(), [](Value result) {
      return freedBy(result.getType(), Release::Scoped);
    }));
    llvm::append_range(outers, stated.drop_front(scoped));
  }
  Operation *made = remakeOp(rewriter, op, op->getOperands(), results);
  if (states)
    rewriter.modifyOpInPlace(made, [&] {
      lifetimes::restateOuters(cast<StatesOutersOpInterface>(made), outers);
    });
  return made;
}

// Every use inside `fn` of a lifetime of owner's scope, read from fn's own:
// each of owner's lifetimes is fn's at the same place, and a view of one
// that its moved code reads, `reads`, is taken again of fn's at its entry.
// Owner's activation, where only loans of static data read it, is fn's own:
// static data outlives every lifetime, so its loan stands in any. Any other
// lifetime ends with owner's call, which nothing moved out of it may read:
// a room carved before it, or a cell in its activation, is memory of that
// call. The decide step keeps every such lifetime out of a function that
// runs a call on frames, so meeting one is its invariant broken.
LogicalResult Component::adoptLifetimes(FuncOp owner, FuncOp fn, llvm::ArrayRef<Value> reads) {
  llvm::SmallVector<BlockArgument> own = lifetimesOf(fn);
  auto within = [&](OpOperand &use) { return fn->isProperAncestor(use.getOwner()); };
  for (auto [mine, theirs] : llvm::zip_equal(own, lifetimesOf(owner)))
    rewriter.replaceUsesWithIf(theirs, mine, within);
  auto lendsStatic = [&](OpOperand &use) {
    auto loan = dyn_cast<CarrierOp>(use.getOwner());
    return !within(use) || (loan && freedBy(loan.getValue().getType(), Release::Static));
  };
  for (Value lifetime : reads) {
    if (lifetime.getParentBlock() == &owner.getBody().front() && isa<BlockArgument>(lifetime))
      continue;
    // One `reads` names twice (code on both sides of a split region reads
    // it) was taken again the first time, and fn reads it no more.
    if (llvm::none_of(lifetime.getUses(), within))
      continue;
    if (lifetime.getDefiningOp<ActivationOp>() && llvm::all_of(lifetime.getUses(), lendsStatic)) {
      // fn's one activation, at the top of its body as every activation
      // is: owner has one, and fn is new, so it had none.
      rewriter.setInsertionPointToStart(&fn.getBody().front());
      Value mine =
          ActivationOp::create(rewriter, lifetime.getLoc(), lifetime.getType()).getLifetime();
      rewriter.replaceUsesWithIf(lifetime, mine, within);
      continue;
    }
    auto forget = lifetime.getDefiningOp<LifetimeForgetOp>();
    std::optional<unsigned> place = placeOf(lifetime, owner);
    if (!forget || !place)
      return owner.emitOpError(
          "internal error: an invariant of idr-lifetimes is broken (idr-frames): a function "
          "that runs a call on frames uses no lifetime but its own, views of them and the "
          "per-level ones directly around such calls, but code that runs after one reads ")
             << lifetime.getType() << " of another";
    rewriter.setInsertionPointToStart(&fn.getBody().front());
    IRMapping view;
    view.map(forget->getOperand(0), own[*place]);
    Operation *again = rewriter.clone(*forget, view);
    rewriter.replaceUsesWithIf(lifetime, again->getResult(0), within);
  }
  return success();
}

} // namespace idr::tail::frames
