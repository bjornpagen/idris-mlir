// The reads of a generate's body at its own index, and the copy of its
// generic that takes the arrays read as inputs where every index is within
// them.

#include "idr/IR/IdrDialect.h"
#include "idr/Conversion/ArrayLoops.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"

#include <optional>

using namespace mlir;

namespace idr::conversion {

namespace {

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
  if (!get || get.getIndices().size() != 1)
    return std::nullopt;
  Value array = viewed(get.getArray());
  Value at = get.getIndices().front();
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
  if (!loopIndex || loopIndex.getDim() != 0 ||
      generic.getRegion().isAncestor(array.getParentRegion()) || !element.isIntOrFloat() ||
      get.getValue().getType() != element)
    return std::nullopt;
  return Read{array, first, guard};
}

} // namespace

void readAsInputs(RewriterBase &rewriter, linalg::GenericOp generic) {
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
    Value last = arith::AddIOp::create(rewriter, loc, length,
                                       arith::ConstantIndexOp::create(rewriter, loc, first));
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
    inputs.push_back(memref::SubViewOp::create(
        rewriter, loc, view, ArrayRef<OpFoldResult>{rewriter.getIndexAttr(first)},
        ArrayRef<OpFoldResult>{length}, ArrayRef<OpFoldResult>{rewriter.getIndexAttr(1)}));
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

} // namespace idr::conversion
