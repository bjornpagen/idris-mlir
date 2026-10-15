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
// program's symbol table where the canonicalizer has one (CalleePattern):
// idr-effects and idr-optimize write them between waves, never while the
// patterns of a function run. Without a table a call may do anything, and
// keeps the read as it is. The pattern rewrites the read and the write, two
// ops, which a folder of either could not.
//
// The pattern is tried at the write and at the read, each reached from the
// other through the world: the driver tells a rewrite to the op it changes,
// and whether the two name one element is a question of both. The read
// leaves the ops between, and so do the rebuilding's ops, which move to the
// write; those ops between whose own question spans the read or a moved op
// are tried again.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;
using namespace idr;

namespace {

// What an op between the read and the write does, with everything in it,
// each a step past the one before: its effects are at most the allocation
// of its own results; it has other effects; or it may read or write an
// array of the read's type, which is an effect too.
enum class Does : uint8_t { Computes, Effects, Touches };

// What `root` does toward an array of type `array`: it reads the IO
// resource (IO may reach any cell, a call through what it is given), it
// reads or writes a value of the array's type, nothing says what it does
// (an op without the interface), or it holds a force. A call's effects on
// the IO, crash and divergence resources are its callee's where `callees`
// says them; what it does to its operands is its own. The ops in a region
// count where their op's effects are its regions' (RecursiveMemoryEffects),
// as upstream gathers them; an op that never runs (ub.unreachable) does
// nothing.
Does doesOf(Operation *root, Type array, const CalleeEffects *callees) {
  auto of = [&](const MemoryEffects::EffectInstance &effect) {
    Value on = effect.getValue();
    if ((isa<MemoryEffects::Read>(effect.getEffect()) &&
         effect.getResource() == IOResource::get()) ||
        (isa<MemoryEffects::Read, MemoryEffects::Write>(effect.getEffect()) && on &&
         unrestricted(on.getType()) == unrestricted(array)))
      return Does::Touches;
    if (!isa<MemoryEffects::Allocate>(effect.getEffect()) || !isa_and_present<OpResult>(on))
      return Does::Effects;
    return Does::Computes;
  };
  Does does = Does::Computes;
  root->walk<WalkOrder::PreOrder>([&](Operation *op) {
    std::optional<SmallVector<MemoryEffects::EffectInstance>> effects = ownEffects(op, callees);
    if (isa<ForceOp>(op) || !effects) {
      does = Does::Touches;
      return WalkResult::interrupt();
    }
    for (const MemoryEffects::EffectInstance &effect : *effects)
      does = std::max(does, of(effect));
    if (does == Does::Touches)
      return WalkResult::interrupt();
    return op->hasTrait<OpTrait::HasRecursiveMemoryEffects>() ? WalkResult::advance()
                                                             : WalkResult::skip();
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

// The write a pattern rooted at `set` asks about: the write itself.
ArraySetOp writeOf(ArraySetOp set) { return set; }

// The write a pattern rooted at `get` asks about: the one use of its next
// world, when that is a write.
ArraySetOp writeOf(ArrayGetOp get) {
  Value next = get.getNext();
  return next.hasOneUse() ? dyn_cast<ArraySetOp>(*next.user_begin()) : ArraySetOp();
}

// The write whose world is the next of a read of the same element in its
// block, with nothing between that may touch the array, becomes the
// element's update; tried at the write and at the read, `Root`.
template <typename Root>
struct MoveOut : canon::CalleePattern {
  MoveOut(MLIRContext *context, const CalleeEffects *callees)
      : CalleePattern(Root::getOperationName(), "idr-move-out", context, callees) {}

  std::unique_ptr<CalleePattern> withCallees(const CalleeEffects *table) const final {
    return std::make_unique<MoveOut>(getContext(), table);
  }

  LogicalResult matchAndRewrite(Operation *root, PatternRewriter &rewriter) const final {
    ArraySetOp set = writeOf(cast<Root>(root));
    if (!set)
      return failure();
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
    llvm::SmallPtrSet<Operation *, 8> rebuilding;
    SmallVector<Operation *> moved;
    SmallVector<bool> computes;
    for (Operation *op = get->getNextNode(); op != set.getOperation(); op = op->getNextNode()) {
      Does does = doesOf(op, array, callees);
      if (does == Does::Touches)
        return failure();
      computes.push_back(does == Does::Computes);
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

    // The read did more than compute, and so may a moved op; each op
    // between was walked above.
    retryBetween(rewriter, {std::next(get->getIterator()), set->getIterator()});
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
  results.add<MoveOut<ArraySetOp>, MoveOut<ArrayGetOp>>(context, /*callees=*/nullptr);
}

} // namespace idr::canon
