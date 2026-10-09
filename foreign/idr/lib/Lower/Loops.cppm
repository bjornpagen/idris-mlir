// idr.lower:loops: phase 1 of idr-lower for the loops over an array's
// index space, after the matches: idr.array.generate and idr.array.fold
// become linalg.generic over the arrays, still on idr types. The arrays
// themselves are the memrefs the generics read and write, and the
// conversion then gives each legal op that holds one its view of the cell
// (:lowering, :arrayView). Everything after is upstream's:
// convert-linalg-to-loops makes the loops, or the vectorizer the vectors.
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
//
// A generate whose body reads arrays from outside at its own index (imap,
// map and zipWith over frozen arrays) reads each with its bounds check,
// which keeps the loop scalar. Where every array it reads is at least as
// long as the new one, which one test on entry decides, every index of the
// loop is within them: there a copy of the generic takes them as inputs,
// each from the first index the loop runs at, and its body only computes,
// since the guard of each such read's index, against its array's length,
// holds there. Otherwise the generic as it was ends the program at the
// first index outside an array, in index order, as the program does.

export module idr.lower:loops;

import idr.mlir;
import idr.dialect;

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

// A read of an array from outside a generic at the generic's index: the
// array, the index the loop's first iteration reads it at (a generate's
// loop runs from its element 1 on, `indexOf`), and the guard of that index
// against the array's length, unless a proof removed it.
struct Read {
  Value array;
  int64_t first = 0;
  CheckInBoundsOp guard;
};

// Whether `length` is the length of `array` as the guard of an access to it
// takes it: the array's one dimension, made i64.
bool isLengthOf(Value length, Value array) {
  auto word = length.getDefiningOp<arith::IndexCastOp>();
  auto dim = word ? word.getIn().getDefiningOp<memref::DimOp>() : memref::DimOp();
  return dim && dim.getConstantIndex() == 0 && viewed(dim.getSource()) == array;
}

// The read `op` is, a word of an array from outside the generic at
// linalg.index 0 plus a constant, as the i64 the body takes, guarded
// against that array's own length or proved within it; none when `op` is
// no such read.
std::optional<Read> readAtIndex(Operation &op, linalg::GenericOp generic) {
  auto get = dyn_cast<ArrayGetOp>(op);
  if (!get)
    return std::nullopt;
  Value array = viewed(get.getArray());
  Value at = get.getIndex();
  auto guard = at.getDefiningOp<CheckInBoundsOp>();
  if (guard) {
    if (!isLengthOf(guard.getLength(), array))
      return std::nullopt;
    at = guard.getIndex();
  }
  auto word = at.getDefiningOp<arith::IndexCastOp>();
  Value index = word ? word.getIn() : Value();
  int64_t first = 0;
  if (auto plus = index ? index.getDefiningOp<arith::AddIOp>() : arith::AddIOp()) {
    std::optional<int64_t> offset = getConstantIntValue(plus.getRhs());
    if (!offset || *offset < 0)
      return std::nullopt;
    first = *offset;
    index = plus.getLhs();
  }
  auto loopIndex = index ? index.getDefiningOp<linalg::IndexOp>() : linalg::IndexOp();
  Type element = get.getArrayType().getElementType();
  if (!loopIndex || loopIndex.getDim() != 0 || generic.getRegion().isAncestor(array.getParentRegion()) ||
      !element.isIntOrFloat() || get.getValue().getType() != element)
    return std::nullopt;
  return Read{array, first, guard};
}

// if (every array the body reads at its index has the elements the loop
// reads) { the generic reading them as inputs } else { the generic }.
void readAsInputs(IRRewriter &rewriter, linalg::GenericOp generic) {
  Block &body = generic.getRegion().front();
  llvm::MapVector<std::pair<Value, int64_t>, unsigned> reads;
  // The guards of those reads' indices, which the test on entry proves.
  DenseSet<Operation *> proved;
  for (Operation &op : body.without_terminator())
    if (std::optional<Read> read = readAtIndex(op, generic)) {
      reads.insert({{read->array, read->first}, reads.size()});
      if (read->guard)
        proved.insert(read->guard);
    }
  if (reads.empty())
    return;
  Location loc = generic.getLoc();
  rewriter.setInsertionPoint(generic);
  Value out = generic.getDpsInits().front();
  Value zero = arith::ConstantIndexOp::create(rewriter, loc, 0);
  // The loop's trip count: the length of the view it writes.
  Value length = rewriter.createOrFold<memref::DimOp>(loc, out, zero);
  Value guard;
  SmallVector<std::pair<Value, int64_t>> arrays;
  for (auto [read, position] : reads) {
    auto [array, first] = read;
    Value view = asMemref(rewriter, loc, array);
    Value last = arith::AddIOp::create(rewriter, loc, length, arith::ConstantIndexOp::create(rewriter, loc, first));
    Value within = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ule, last,
                                         memref::DimOp::create(rewriter, loc, view, zero));
    guard = guard ? Value(arith::AndIOp::create(rewriter, loc, guard, within)) : within;
    arrays.push_back({view, first});
  }
  auto branch = scf::IfOp::create(rewriter, loc, TypeRange{}, guard, /*withElseRegion=*/true);
  // Each input the `length` elements of an array from the one the first
  // iteration reads, which the test says it has.
  rewriter.setInsertionPointToStart(branch.thenBlock());
  SmallVector<Value> inputs;
  for (auto [view, first] : arrays)
    inputs.push_back(memref::SubViewOp::create(rewriter, loc, view, ArrayRef<OpFoldResult>{rewriter.getIndexAttr(first)},
                                               ArrayRef<OpFoldResult>{length},
                                               ArrayRef<OpFoldResult>{rewriter.getIndexAttr(1)}));
  SmallVector<AffineMap> maps(inputs.size() + 1, generic.getIndexingMapsArray().front());
  auto fast = linalg::GenericOp::create(
      rewriter, loc, inputs, ValueRange{out}, maps, generic.getIteratorTypesArray(),
      [&](OpBuilder &b, Location, ValueRange args) {
        IRMapping mapping;
        mapping.map(body.getArgument(0), args.back());
        for (Operation &op : body) {
          if (proved.contains(&op)) {
            auto checked = cast<CheckInBoundsOp>(op);
            mapping.map(checked.getChecked(), mapping.lookupOrDefault(checked.getIndex()));
            continue;
          }
          if (std::optional<Read> read = readAtIndex(op, generic)) {
            auto get = cast<ArrayGetOp>(op);
            mapping.map(get.getValue(), args[reads.lookup({read->array, read->first})]);
            mapping.map(get.getNext(), mapping.lookupOrDefault(get.getWorld()));
            continue;
          }
          b.clone(op, mapping);
        }
      });
  // The views and worlds the reads took are left unused.
  for (Operation &op : llvm::make_early_inc_range(llvm::reverse(fast.getRegion().front())))
    if (isOpTriviallyDead(&op))
      rewriter.eraseOp(&op);
  rewriter.moveOpBefore(generic, branch.elseBlock()->getTerminator());
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
    auto generic = linalg::GenericOp::create(
        rewriter, loc, ValueRange{}, ValueRange{out}, ArrayRef<AffineMap>{identity},
        ArrayRef<utils::IteratorType>{parallel}, [&](OpBuilder &b, Location l, ValueRange) {
          IRMapping mapping;
          mapping.map(body.getArgument(0), indexOf(b, l, 0, 1));
          linalg::YieldOp::create(b, l, cloneBody(b, l, body, mapping, nullptr, element));
        });
    readAsInputs(rewriter, generic);
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
export void lowerArrayLoops(ModuleOp module) {
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
