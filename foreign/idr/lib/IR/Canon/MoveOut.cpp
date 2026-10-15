// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A read of an element whose next IO is a write of the same element becomes
// that element's update (idr.array.update): the element moves out of the
// array, with the reference the array held, into a region that rebuilds it,
// and the region's first value moves back in. So a value read only to be
// rebuilt and written back (an IORef's modify, a state record's update, a
// read and a write of one element of an array) holds the one reference to
// its cell while it is rebuilt, and counting rebuilds it in that cell. The
// rule names no definition: what it asks is where the world goes.
//
// The world is linear and the read's next world has one use, the write, so
// no IO threaded on that world lies between them. The ops between that read
// the element, directly or through one another, are the rebuilding: they
// move into the region, which sits where the write was, and each value of
// theirs, or the element itself, still used after the write leaves the
// update as one of its results. The region binds no world, so the
// rebuilding takes and gives none. While it runs the element's place is
// empty, and before it the read has not happened, so nothing between may
// read or write the array: IO on a world of its own (a trusted library's
// forged one), a call that performs IO, code whose effects MLIR does not
// know, and a force, whose declared effects do not say what its
// suspension's code reads, each keep the read as it is. The rebuilding moves
// past the other ops between toward the write: an op of it that does more
// than compute moves past only ops that only compute, so every effect keeps
// its order.
//
// A call does what its callee's effects say, the one copy, read through the
// program's symbol table: idr-effects and idr-optimize write them between
// waves, never while the patterns of a function run. The pattern rewrites
// the read, another op than the write it is rooted at, which a folder of
// the write could not.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Func.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;
using namespace idr;

namespace {

// What an op between the read and the write does, with everything in it.
struct Does {
  // It may read or write an array of the read's type.
  bool touches = false;
  // Its effects are at most the allocation of its own results.
  bool computes = true;
};

// What `root` does toward an array of type `array`: it reads the IO
// resource (IO may reach any cell, a call through what it is given), it
// reads or writes a value of the array's type, nothing says what it does
// (an op without the interface), or it holds a force. A call's effects on
// the IO, crash and divergence resources are its callee's; what it does to
// its operands is its own. The ops in a region count where their op's
// effects are its regions' (RecursiveMemoryEffects), as upstream gathers
// them; an op that never runs (ub.unreachable) does nothing.
Does doesOf(Operation *root, Type array, SymbolTableCollection &symbols) {
  Does does;
  auto note = [&](const MemoryEffects::EffectInstance &effect) {
    Value on = effect.getValue();
    if ((isa<MemoryEffects::Read>(effect.getEffect()) &&
         effect.getResource() == IOResource::get()) ||
        (isa<MemoryEffects::Read, MemoryEffects::Write>(effect.getEffect()) && on &&
         unrestricted(on.getType()) == unrestricted(array)))
      does.touches = true;
    if (!isa<MemoryEffects::Allocate>(effect.getEffect()) || !isa_and_present<OpResult>(on))
      does.computes = false;
  };
  root->walk<WalkOrder::PreOrder>([&](Operation *op) {
    if (isa<ForceOp>(op)) {
      does = {/*touches=*/true, /*computes=*/false};
      return WalkResult::interrupt();
    }
    if (isa<ub::UnreachableOp>(op))
      return WalkResult::advance();
    auto call = dyn_cast<CallOpInterface>(op);
    if (call) {
      Effect callee = effectsOf(call, symbols);
      does.touches |= bitEnumContainsAny(callee, Effect::io);
      does.computes &= callee == Effect::none;
    }
    bool recursive = op->hasTrait<OpTrait::HasRecursiveMemoryEffects>();
    auto iface = dyn_cast<MemoryEffectOpInterface>(op);
    if (!iface) {
      if (recursive || call)
        return WalkResult::advance();
      does = {/*touches=*/true, /*computes=*/false};
      return WalkResult::interrupt();
    }
    SmallVector<MemoryEffects::EffectInstance> effects;
    iface.getEffects(effects);
    for (const MemoryEffects::EffectInstance &effect : effects)
      if (!call || (effect.getResource() != IOResource::get() &&
                    effect.getResource() != CrashResource::get() &&
                    effect.getResource() != DivergenceResource::get()))
        note(effect);
    return recursive ? WalkResult::advance() : WalkResult::skip();
  });
  return does;
}

// Whether `op`, or an op in it, takes or gives a world.
bool usesWorld(Operation *op) {
  return op
      ->walk([](Operation *inner) {
        return llvm::any_of(inner->getOperandTypes(), holdsWorld) ||
                       llvm::any_of(inner->getResultTypes(), holdsWorld)
                   ? WalkResult::interrupt()
                   : WalkResult::advance();
      })
      .wasInterrupted();
}

// Whether `op`, or an op in it, uses `element` or a result of an op of
// `rebuilding`.
bool readsFrom(Operation *op, Value element, const llvm::SmallPtrSetImpl<Operation *> &rebuilding) {
  return op
      ->walk([&](Operation *inner) {
        return llvm::any_of(inner->getOperands(),
                            [&](Value operand) {
                              Operation *def = operand.getDefiningOp();
                              return operand == element || (def && rebuilding.contains(def));
                            })
                   ? WalkResult::interrupt()
                   : WalkResult::advance();
      })
      .wasInterrupted();
}

// The write whose world is the next of a read of the same element in its
// block, with nothing between that may touch the array, becomes the
// element's update.
struct MoveOutBeforeSet : OpRewritePattern<ArraySetOp> {
  using OpRewritePattern::OpRewritePattern;
  LogicalResult matchAndRewrite(ArraySetOp set, PatternRewriter &rewriter) const final {
    auto get = set.getWorld().getDefiningOp<ArrayGetOp>();
    if (!get || !get.getNext().hasOneUse() || get->getBlock() != set->getBlock() ||
        !sameElement(get.getArray(), get.getIndices(), set.getArray(), set.getIndices()))
      return failure();
    // An element that holds no reference has none to give up.
    if (!holdsReferences(get.getArrayType().getElementType()))
      return failure();
    Value element = get.getValue();
    Type array = get.getArray().getType();

    // The rebuilding, in order, and what each op between does.
    SymbolTableCollection symbols;
    llvm::SmallPtrSet<Operation *, 8> rebuilding;
    SmallVector<Operation *> moved;
    SmallVector<bool> computes;
    for (Operation *op = get->getNextNode(); op != set.getOperation(); op = op->getNextNode()) {
      Does does = doesOf(op, array, symbols);
      if (does.touches)
        return failure();
      computes.push_back(does.computes);
      if (!readsFrom(op, element, rebuilding))
        continue;
      if (usesWorld(op))
        return failure();
      rebuilding.insert(op);
      moved.push_back(op);
    }
    // From the write back: whether an op the rebuilding moves past does
    // more than compute.
    bool effectAfter = false;
    size_t at = computes.size();
    for (Operation *op = set->getPrevNode(); op != get.getOperation(); op = op->getPrevNode()) {
      bool computesHere = computes[--at];
      if (!rebuilding.contains(op))
        effectAfter |= !computesHere;
      else if (!computesHere && effectAfter)
        return failure();
    }

    // What leaves the update: the element and the rebuilding's values that
    // some op after the write uses, the write itself aside.
    Block *block = set->getBlock();
    auto usedAfter = [&](Value value) {
      return llvm::any_of(value.getUses(), [&](OpOperand &use) {
        Operation *ancestor = block->findAncestorOpInBlock(*use.getOwner());
        return ancestor != set.getOperation() && !(ancestor && rebuilding.contains(ancestor));
      });
    };
    SmallVector<Value> leaving;
    if (usedAfter(element))
      leaving.push_back(element);
    for (Operation *op : moved)
      for (Value result : op->getResults())
        if (usedAfter(result))
          leaving.push_back(result);

    Location loc = rewriter.getFusedLoc({get.getLoc(), set.getLoc()});
    rewriter.setInsertionPoint(set);
    auto update = ArrayUpdateOp::create(rewriter, loc, ValueRange(leaving).getTypes(),
                                        set.getNext().getType(), get.getArray(),
                                        get.getIndices(), get.getWorld());
    Block *body = rewriter.createBlock(&update.getRegion(), {}, {element.getType()},
                                       {get.getLoc()});
    for (Operation *op : moved)
      rewriter.moveOpBefore(op, body, body->end());
    Value moving = update.getElement();
    rewriter.replaceUsesWithIf(element, moving, [&](OpOperand &use) {
      return update->isProperAncestor(use.getOwner());
    });
    auto inside = [&](Value value) { return value == element ? moving : value; };
    SmallVector<Value> yielded{inside(set.getValue())};
    llvm::append_range(yielded, llvm::map_range(leaving, inside));
    ArrayYieldOp::create(rewriter, loc, yielded);
    for (auto [value, out] : llvm::zip_equal(leaving, update.getOuts()))
      rewriter.replaceUsesWithIf(value, out, [&](OpOperand &use) {
        return use.getOwner() != set.getOperation() && !update->isAncestor(use.getOwner());
      });
    rewriter.replaceOp(set, update.getNext());
    rewriter.eraseOp(get);
    return success();
  }
};

} // namespace

namespace idr::canon {

void addMoveOutPatterns(RewritePatternSet &results, MLIRContext *context) {
  results.add<MoveOutBeforeSet>(context);
}

} // namespace idr::canon
