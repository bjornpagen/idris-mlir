// Phase 1 of idr-lower for the loops over an array's index space:
// idr.array.generate and idr.array.fold become linalg.generic over the
// arrays, still on idr types. The arrays themselves are the memrefs the
// generics read and write, and the conversion then gives each legal op
// that holds one its view of the cell (Pass.cc, Arrays.cc). Everything
// after is upstream's: convert-linalg-to-loops makes the loops, or the
// vectorizer the vectors.
//
// A generate is a parallel generic over a view of the new array from
// element 1 on (idr.array.new makes the array, filled as the op's fill
// says, and the fill is element 0), its body yielding each element from
// linalg.index 0 plus one: the body runs at every index but 0, whose
// element is the fill. A fold is a reduction generic over its array into a
// 0-d memref holding the accumulator, a slot in the function's frame
// (memref.alloca at the entry, so a fold inside a loop takes one slot, not
// one per iteration): the init is stored first and the result loaded
// after. The reduction keeps the program's order: linalg runs a reduction
// dimension in index order, in loops as one scf.for, and the vectorizer's
// schedule never gives a reduction dimension more than one lane, so a
// floating accumulator adds the elements as the program does.
//
// A generate whose body is a fold over an array from outside (each element
// a row's reduction: spectral-norm's rows) is one generic of two
// dimensions, parallel then reduction, with the element's accumulator in
// the new array itself: a first parallel generic writes each element's
// init, the second reduces into it, both over the elements from 1 on. The
// body's other ops, which compute from the index alone, go into both; the
// fold's body follows them with the accumulator as the output element, the
// element as the input and the index from linalg.index 1. That is the form
// the vectorizer tiles along the parallel dimension, each lane summing its
// row in order.

#include "Lower/Patterns.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;

namespace idr::lower {

namespace {

// The array as a memref a linalg op reads or writes: itself, or a view of
// an owned one.
Value asMemref(OpBuilder &b, Location loc, Value array) {
  return isOwned(array.getType()) ? BorrowOp::create(b, loc, array).getResult() : array;
}

// The index of dimension `dim` of the generic around the insertion point,
// counted from `first`, as the i64 the body takes.
Value indexOf(OpBuilder &b, Location loc, uint64_t dim, int64_t first = 0) {
  Value index = linalg::IndexOp::create(b, loc, dim);
  if (first != 0)
    index = arith::AddIOp::create(b, loc, index, arith::ConstantIndexOp::create(b, loc, first));
  return arith::IndexCastOp::create(b, loc, b.getI64Type(), index);
}

// The elements of a new array of `size` elements from index 1 on, a view of
// `array`: what a generate's body writes, element 0 being the fill. There
// are max(size, 1) - 1 of them, which is 0 for every size up to 1 and,
// unlike size - 1, does not wrap where size is the least i64.
Value fromSecond(OpBuilder &b, Location loc, Value array, Value size) {
  Value one = arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(1));
  Value rest = arith::SubIOp::create(b, loc, arith::MaxSIOp::create(b, loc, size, one), one);
  OpFoldResult unit = b.getIndexAttr(1);
  OpFoldResult length = arith::IndexCastOp::create(b, loc, b.getIndexType(), rest).getResult();
  return memref::SubViewOp::create(b, loc, array, ArrayRef<OpFoldResult>{unit},
                                   ArrayRef<OpFoldResult>{length}, ArrayRef<OpFoldResult>{unit});
}

// Clones the ops of `block` but its terminator (and `except`) at the
// insertion point, `mapping` saying what its arguments stand for; gives
// the terminator's operand as mapped, or poison of `type` after a body
// that never returns, whose crash before it is never passed.
Value cloneBody(OpBuilder &b, Location loc, Block &block, IRMapping &mapping, Operation *except,
                Type type) {
  for (Operation &op : block.without_terminator())
    if (&op != except)
      b.clone(op, mapping);
  if (auto yield = dyn_cast<YieldOp>(block.getTerminator()))
    return mapping.lookupOrDefault(yield.getOperand(0));
  return ub::PoisonOp::create(b, loc, type);
}

// The array a view was read from, through the borrows (idr-rc reads an
// owned array where the fold is, inside the body, so the fold's operand
// is a view of a value from outside).
Value viewed(Value array) {
  while (auto borrow = array.getDefiningOp<BorrowOp>())
    array = borrow.getValue();
  return array;
}

// The fold a generate's body is: its yield is the result of a fold over an
// array from outside the body, and every other op in the body only
// computes (a forged world and a view included, which lower to nothing).
// Null otherwise.
ArrayFoldOp reducedBy(ArrayGenerateOp op) {
  Block &body = op.getBody().front();
  auto yield = dyn_cast<YieldOp>(body.getTerminator());
  if (!yield)
    return {};
  auto fold = yield.getOperand(0).getDefiningOp<ArrayFoldOp>();
  if (!fold || fold->getBlock() != &body ||
      op.getBody().isAncestor(viewed(fold.getArray()).getParentRegion()))
    return {};
  for (Operation &inner : body.without_terminator())
    if (&inner != fold && !isMemoryEffectFree(&inner) && !isa<WorldNewOp, BorrowOp>(inner))
      return {};
  return fold;
}

void lowerGenerate(IRRewriter &rewriter, ArrayGenerateOp op) {
  Location loc = op.getLoc();
  MLIRContext *ctx = op.getContext();
  rewriter.setInsertionPoint(op);
  auto made = ArrayNewOp::create(rewriter, loc, op.getArray().getType(), op.getNext().getType(),
                                 op.getSize(), op.getFill(), op.getWorld());
  Value out = fromSecond(rewriter, loc, asMemref(rewriter, loc, made.getArray()), op.getSize());
  Block &body = op.getBody().front();
  Type element = op.getArrayType().getElementType();
  AffineMap identity = AffineMap::getMultiDimIdentityMap(1, ctx);
  auto parallel = utils::IteratorType::parallel;
  if (ArrayFoldOp fold = reducedBy(op)) {
    Value in = asMemref(rewriter, loc, viewed(fold.getArray()));
    Block &reduce = fold.getBody().front();
    // The body's ops but the fold, from the index: what the fold's init
    // and body compute with.
    auto prelude = [&](OpBuilder &b, Location l, IRMapping &mapping) {
      mapping.map(body.getArgument(0), indexOf(b, l, 0, 1));
      for (Operation &inner : body.without_terminator())
        if (&inner != fold)
          b.clone(inner, mapping);
    };
    linalg::GenericOp::create(rewriter, loc, ValueRange{}, ValueRange{out}, ArrayRef<AffineMap>{identity},
                              ArrayRef<utils::IteratorType>{parallel},
                              [&](OpBuilder &b, Location l, ValueRange) {
                                IRMapping mapping;
                                prelude(b, l, mapping);
                                linalg::YieldOp::create(b, l, mapping.lookupOrDefault(fold.getInit()));
                              });
    AffineMap column = AffineMap::get(2, 0, {getAffineDimExpr(1, ctx)}, ctx);
    AffineMap row = AffineMap::get(2, 0, {getAffineDimExpr(0, ctx)}, ctx);
    linalg::GenericOp::create(
        rewriter, loc, ValueRange{in}, ValueRange{out}, ArrayRef<AffineMap>{column, row},
        ArrayRef<utils::IteratorType>{parallel, utils::IteratorType::reduction},
        [&](OpBuilder &b, Location l, ValueRange args) {
          IRMapping mapping;
          prelude(b, l, mapping);
          mapping.map(reduce.getArgument(0), args[1]);
          mapping.map(reduce.getArgument(1), args[0]);
          mapping.map(reduce.getArgument(2), indexOf(b, l, 1));
          linalg::YieldOp::create(b, l, cloneBody(b, l, reduce, mapping, nullptr, element));
        });
  } else {
    linalg::GenericOp::create(rewriter, loc, ValueRange{}, ValueRange{out}, ArrayRef<AffineMap>{identity},
                              ArrayRef<utils::IteratorType>{parallel},
                              [&](OpBuilder &b, Location l, ValueRange) {
                                IRMapping mapping;
                                mapping.map(body.getArgument(0), indexOf(b, l, 0, 1));
                                linalg::YieldOp::create(b, l, cloneBody(b, l, body, mapping, nullptr, element));
                              });
  }
  rewriter.replaceOp(op, {made.getArray(), made.getNext()});
}

void lowerFold(IRRewriter &rewriter, ArrayFoldOp op) {
  Location loc = op.getLoc();
  MLIRContext *ctx = op.getContext();
  Type acc = unrestricted(op.getInit().getType());
  Value slot;
  {
    OpBuilder::InsertionGuard guard(rewriter);
    rewriter.setInsertionPointToStart(&op->getParentOfType<func::FuncOp>().getBody().front());
    slot = memref::AllocaOp::create(rewriter, loc, MemRefType::get({}, acc));
  }
  rewriter.setInsertionPoint(op);
  memref::StoreOp::create(rewriter, loc, op.getInit(), slot, ValueRange{});
  Value in = asMemref(rewriter, loc, op.getArray());
  Block &body = op.getBody().front();
  AffineMap identity = AffineMap::getMultiDimIdentityMap(1, ctx);
  AffineMap scalar = AffineMap::get(1, 0, ctx);
  linalg::GenericOp::create(rewriter, loc, ValueRange{in}, ValueRange{slot},
                            ArrayRef<AffineMap>{identity, scalar},
                            ArrayRef<utils::IteratorType>{utils::IteratorType::reduction},
                            [&](OpBuilder &b, Location l, ValueRange args) {
                              IRMapping mapping;
                              mapping.map(body.getArgument(0), args[1]);
                              mapping.map(body.getArgument(1), args[0]);
                              mapping.map(body.getArgument(2), indexOf(b, l, 0));
                              linalg::YieldOp::create(b, l, cloneBody(b, l, body, mapping, nullptr, acc));
                            });
  Value result = memref::LoadOp::create(rewriter, loc, slot, ValueRange{});
  rewriter.replaceOp(op, {result, op.getWorld()});
}

} // namespace

// Outermost first: a generate sees the fold its body is before anything
// lowers it; a fold the body only holds is cloned into the generic with
// the body, and lowers in its turn.
void lowerArrayLoops(ModuleOp module) {
  IRRewriter rewriter(module.getContext());
  for (;;) {
    Operation *next = nullptr;
    module.walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (!isa<ArrayGenerateOp, ArrayFoldOp>(op))
        return WalkResult::advance();
      next = op;
      return WalkResult::interrupt();
    });
    if (!next)
      return;
    if (auto generate = dyn_cast<ArrayGenerateOp>(next))
      lowerGenerate(rewriter, generate);
    else
      lowerFold(rewriter, cast<ArrayFoldOp>(next));
  }
}

} // namespace idr::lower
