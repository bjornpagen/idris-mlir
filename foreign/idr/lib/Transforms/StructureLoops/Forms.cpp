// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op of the generating set becomes. Its iterator types say which
// dimensions its region leaves free; the arrays it writes and reads say
// whether a linalg op may hold them. A region that only computes, over
// arrays of words, keeps a parallel dimension parallel; a fold's ordered
// dimension becomes a reduction only where each combiner is one integer op
// whose law lets it run in any order. A float sum keeps its order on every
// target. Every other op stays as it is, for its loops, and so does an op
// whose region calls.
//
// The facts each form rests on are the IR's: effects through the region's
// own (the iterator types), the laws through the combining op, and the
// equality of sizes through value bounds, which idr.array.tie_shape carries
// across calls.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallSet.h"

using namespace mlir;

namespace idr::structure {

namespace {

// The words: the element types a vector holds and a linalg op computes on.
bool isWord(Type type) { return type.isIntOrIndexOrFloat(); }

// Whether `type` is an array whose elements are no words.
bool notWords(Type type) {
  auto array = dyn_cast<RankedTensorType>(type);
  return array && !isWord(array.getElementType());
}

// Whether the arrays `op` writes and reads hold words, its region gives a
// word at each index (an element, never a cell) and binds a word for each
// accumulator, and reads, makes or carries no array of other elements: the
// arrays of non-word elements never reach a linalg op, since no linalg
// body holds a reference while counting runs. A dimension asked of such an
// array reads none of its elements.
bool overWords(Operation *op) {
  Block &body = op->getRegion(0).front();
  auto words = [](Type type) { return isWord(type); };
  if (llvm::any_of(op->getOperandTypes(), notWords) ||
      !llvm::all_of(body.getArgumentTypes(), words))
    return false;
  if (auto yield = dyn_cast<ArrayYieldOp>(body.getTerminator());
      yield && !llvm::all_of(yield.getValues().getTypes(), words))
    return false;
  return !op->getRegion(0)
              .walk([](Operation *inner) {
                if (isa<tensor::DimOp>(inner))
                  return WalkResult::advance();
                bool other = llvm::any_of(inner->getOperandTypes(), notWords) ||
                             llvm::any_of(inner->getResultTypes(), notWords);
                return other ? WalkResult::interrupt() : WalkResult::advance();
              })
              .wasInterrupted();
}

// Whether `op`'s region makes a call. No linalg body that calls is
// vectorized, and a call on its function's own cycle must stand where
// frames can split it, in the op's join-point loops, which a pass on one
// function cannot tell from any other call: so a region that calls keeps
// its op for its loops.
bool calls(Operation *op) {
  return op->getRegion(0)
      .walk([](CallOpInterface) { return WalkResult::interrupt(); })
      .wasInterrupted();
}

// Whether each next accumulator of `fold` is one associative and
// commutative integer op of its accumulator and a value that no other
// accumulator reaches: the accumulator's one use, giving the yield's one
// operand. An op marked nsw or nuw is no such combiner: reassociated, it
// could overflow where the program did not.
bool reassociates(ArrayFoldLastOp fold) {
  auto yield = cast<ArrayYieldOp>(fold.getBody()->getTerminator());
  for (auto [accumulator, next] : llvm::zip_equal(fold.getAccumulators(), yield.getValues())) {
    Operation *combine = next.getDefiningOp();
    if (!combine || combine->getBlock() != fold.getBody() ||
        !isa<arith::AddIOp, arith::MulIOp, arith::AndIOp, arith::OrIOp, arith::XOrIOp,
             arith::MinSIOp, arith::MinUIOp, arith::MaxSIOp, arith::MaxUIOp>(combine) ||
        !accumulator.hasOneUse() || !next.hasOneUse() ||
        (combine->getOperand(0) == accumulator) == (combine->getOperand(1) == accumulator))
      return false;
    if (auto flags = dyn_cast<arith::ArithIntegerOverflowFlagsInterface>(combine);
        flags && flags.getOverflowAttr().getValue() != arith::IntegerOverflowFlags::none)
      return false;
  }
  return true;
}

// Whether two sizes are one, as value bounds proves it; what it cannot
// prove is not.
bool same(const ValueBoundsConstraintSet::Variable &a,
          const ValueBoundsConstraintSet::Variable &b) {
  FailureOr<bool> equal = ValueBoundsConstraintSet::areEqual(a, b);
  return succeeded(equal) && *equal;
}

} // namespace

SmallVector<Read> readsOf(Operation *op, unsigned dims) {
  auto dps = cast<DestinationStyleOpInterface>(op);
  Region &region = op->getRegion(0);
  Block &body = region.front();
  MLIRContext *ctx = op->getContext();
  SmallVector<Read> reads;
  for (Operation &inner : body.without_terminator()) {
    auto read = dyn_cast<tensor::ExtractOp>(&inner);
    if (!read || !isWord(read.getType()) || region.isAncestor(read.getTensor().getParentRegion()))
      continue;
    SmallVector<AffineExpr> exprs;
    llvm::SmallSet<unsigned, 4> seen;
    for (auto [at, index] : llvm::enumerate(read.getIndices())) {
      auto arg = dyn_cast<BlockArgument>(index);
      if (!arg || arg.getOwner() != &body || arg.getArgNumber() >= dims ||
          !seen.insert(arg.getArgNumber()).second ||
          !same({read.getTensor(), static_cast<int64_t>(at)},
                arrays::extentOf(dps, arg.getArgNumber())))
        break;
      exprs.push_back(getAffineDimExpr(arg.getArgNumber(), ctx));
    }
    if (exprs.size() == read.getIndices().size())
      reads.push_back({read, AffineMap::get(dims, 0, exprs, ctx)});
  }
  return reads;
}

Form formOf(Operation *op) {
  // The parallel dimensions lead; what follows them is ordered. An op whose
  // region does more than compute visits every dimension in order.
  SmallVector<utils::IteratorType> iterators = cast<TilingInterface>(op).getLoopIteratorTypes();
  auto rank = static_cast<unsigned>(iterators.size());
  auto frame = static_cast<unsigned>(llvm::count(iterators, utils::IteratorType::parallel));
  if (frame == 0 || !overWords(op) || calls(op))
    return Form::Ordered;
  if (frame == rank)
    return Form::Parallel;
  // Of the two folds along the last axis, the scan keeps every step, so
  // only the fold may combine its steps in another order. A reduction's
  // extent is the size of an input along it: linalg reads the domain off
  // its operands.
  if (auto fold = dyn_cast<ArrayFoldLastOp>(op)) {
    AffineExpr last = getAffineDimExpr(frame, op->getContext());
    bool extent = llvm::any_of(readsOf(fold, frame + 1), [&](const Read &read) {
      return llvm::is_contained(read.map.getResults(), last);
    });
    if (extent && reassociates(fold))
      return Form::Reduction;
  }
  return Form::Interchange;
}

} // namespace idr::structure
