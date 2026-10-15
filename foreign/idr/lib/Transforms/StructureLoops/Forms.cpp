// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op of the generating set is lowered to. The op says how it visits
// each dimension; what its region does says whether that visit's freedom is
// kept. A region that does no more than compute and crash, over arrays of
// words, keeps a parallel dimension parallel; a fold's ordered dimension
// becomes a reduction only where each combiner is one integer op whose law
// lets it run in any order. A float sum keeps its order on every target.
//
// The facts each form rests on are the IR's: effects through
// MemoryEffectOpInterface and a callee's final effects, the laws through
// the combining op, and the equality of sizes through value bounds, which
// idr.tie_shape carries across calls.

#include "idr/Transforms/StructureLoops.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
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

// Whether `op` itself does no more than compute, allocate its own results
// and crash. A call does what its callee's final effects say. A crash
// writes the crash resource, and the IO resource to keep its order with
// output, which is its own and no output.
bool atMostCrashes(Operation *op, const CalleeEffects &callees) {
  std::optional<SmallVector<MemoryEffects::EffectInstance>> effects = ownEffects(op, &callees);
  if (!effects)
    return false;
  auto crash = dyn_cast<MayCrashOpInterface>(op);
  bool crashes = crash && crash.getCrashCause().has_value();
  return llvm::all_of(*effects, [&](const MemoryEffects::EffectInstance &effect) {
    if (isa<MemoryEffects::Allocate>(effect.getEffect())) {
      auto made = dyn_cast_or_null<OpResult>(effect.getValue());
      return made && made.getOwner() == op;
    }
    if (!isa<MemoryEffects::Write>(effect.getEffect()))
      return false;
    return effect.getResource() == CrashResource::get() ||
           (crashes && effect.getResource() == IOResource::get());
  });
}

// Whether the region of `op` returns, and does no more than compute and
// crash, its every op asked on its own.
bool computes(Operation *op, const CalleeEffects &callees) {
  Region &region = op->getRegion(0);
  if (!isa<ArrayYieldOp>(region.front().getTerminator()))
    return false;
  return !region
              .walk([&](Operation *inner) {
                return atMostCrashes(inner, callees) ? WalkResult::advance()
                                                     : WalkResult::interrupt();
              })
              .wasInterrupted();
}

// Whether the arrays `op` makes and folds hold words, each element one,
// and its region reads, makes or carries no array of other elements: the
// arrays of non-word elements never reach a linalg op. A dimension asked
// of such an array reads none of its elements.
bool overWords(Operation *op, TypeRange arrays, unsigned rank) {
  for (Type type : arrays) {
    auto array = cast<RankedTensorType>(type);
    if (!isWord(array.getElementType()) || array.getRank() != rank)
      return false;
  }
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

// Whether each next accumulator of `fold` is one associative and
// commutative integer op of its accumulator and a value that no other
// accumulator reaches: the accumulator's one use, giving the yield's one
// operand. An op marked nsw or nuw is no such combiner: reassociated, it
// could overflow where the program did not.
bool reassociates(FoldLastOp fold) {
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

bool structurable(Operation *op) {
  return isa<TabulateOp, TabulateIOOp, FoldLastOp, ScanLastOp, TransposeOp>(op);
}

SmallVector<Read> readsOf(Operation *op, unsigned dims) {
  auto generating = cast<GeneratingOpInterface>(op);
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
                generating.getExtentBound(arg.getArgNumber())))
        break;
      exprs.push_back(getAffineDimExpr(arg.getArgNumber(), ctx));
    }
    if (exprs.size() == read.getIndices().size())
      reads.push_back({read, AffineMap::get(dims, 0, exprs, ctx)});
  }
  return reads;
}

Form formOf(Operation *op, const CalleeEffects &callees) {
  if (auto transpose = dyn_cast<TransposeOp>(op))
    return isWord(transpose.getType().getElementType()) ? Form::Parallel : Form::Ordered;
  // A world carried from step to step is an order no linalg op keeps.
  if (isa<TabulateIOOp>(op))
    return Form::Ordered;
  // The parallel dimensions lead; what follows them is ordered.
  auto generating = cast<GeneratingOpInterface>(op);
  SmallVector<Iteration> iterations = generating.getIterations();
  auto frame = static_cast<unsigned>(llvm::count(iterations, Iteration::Parallel));
  if (!computes(op, callees) || !overWords(op, generating.getHeldArrays().getTypes(), frame))
    return Form::Ordered;
  if (frame == iterations.size())
    return Form::Parallel;
  // A reduction's extent is the size of an input along it: linalg reads the
  // domain off its operands.
  if (auto fold = dyn_cast<FoldLastOp>(op)) {
    AffineExpr last = getAffineDimExpr(frame, op->getContext());
    bool extent = llvm::any_of(readsOf(fold, frame + 1), [&](const Read &read) {
      return llvm::is_contained(read.map.getResults(), last);
    });
    if (extent && reassociates(fold))
      return Form::Reduction;
  }
  return frame > 0 ? Form::Interchange : Form::Ordered;
}

} // namespace idr::structure
