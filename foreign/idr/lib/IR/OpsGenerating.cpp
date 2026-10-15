// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules the ops on arrays share, each said once (idr/IR/Arrays.h); and
// the ops of the generating set that make no region of their own: the
// transpose, a whole array moved, and the yield that ends every region of
// an array op.

#include "idr/IR/Arrays.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/Dialect/Utils/IndexingUtils.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace idr;

namespace idr::arrays {

// What each rule says is in idr/IR/Arrays.h.

Type cellOf(RankedTensorType array, unsigned lead) {
  if (lead == array.getRank())
    return array.getElementType();
  return RankedTensorType::get(array.getShape().drop_front(lead), array.getElementType());
}

bool sameLead(RankedTensorType a, RankedTensorType b, unsigned lead) {
  return a.getRank() >= lead && b.getRank() >= lead &&
         a.getShape().take_front(lead) == b.getShape().take_front(lead);
}

FlowPoint elementsOf(Value array) {
  auto shaped = cast<ShapedType>(unrestricted(array.getType()));
  return FlowPoint::partOf(array, FlowAnchor::elementsOf(shaped.getElementType()));
}

FlowPoint atIndex(OpOperand &use) {
  if (auto cell = dyn_cast<RankedTensorType>(use.get().getType()))
    return FlowPoint::partOf(use, FlowAnchor::elementsOf(cell.getElementType()));
  return FlowPoint::of(use);
}
FlowPoint atIndex(Value value) {
  if (isa<RankedTensorType>(value.getType()))
    return elementsOf(value);
  return FlowPoint::of(value);
}

void generatingSuccessors(Operation *op, SmallVectorImpl<RegionSuccessor> &regions) {
  regions.push_back(RegionSuccessor(&op->getRegion(0)));
  regions.push_back(RegionSuccessor(op));
}

LogicalResult verifyEnd(Operation *op, TypeRange types, function_ref<bool(unsigned)> graded) {
  Operation *end = op->getRegion(0).front().getTerminator();
  if (isa<ub::UnreachableOp>(end))
    return success();
  auto yield = dyn_cast<ArrayYieldOp>(end);
  if (!yield)
    return op->emitOpError("ends its region in ") << end->getName()
                                                  << ", not idr.array.yield or ub.unreachable";
  if (yield.getValues().size() != types.size())
    return yield.emitOpError("yields ") << yield.getValues().size() << " values where "
                                        << op->getName() << " takes " << types.size();
  for (auto [at, value, type] : llvm::enumerate(yield.getValues(), types)) {
    bool any = graded && graded(static_cast<unsigned>(at));
    if (any ? view(value.getType()) != type : value.getType() != type)
      return yield.emitOpError("yields ")
             << value.getType() << " at " << at << " where " << op->getName() << " takes "
             << type;
  }
  return success();
}

LogicalResult verifyIndices(Operation *op, unsigned rank) {
  Block &body = op->getRegion(0).front();
  if (body.getNumArguments() < rank)
    return op->emitOpError("binds ")
           << body.getNumArguments() << " values in its region, fewer than " << rank;
  for (BlockArgument index : body.getArguments().take_front(rank))
    if (!index.getType().isIndex())
      return op->emitOpError("binds ") << index.getType() << " where its region binds an index";
  return success();
}

void boundIndex(Value value, Block::BlockArgListType indices,
                function_ref<AffineExpr(unsigned)> extent, ValueBoundsConstraintSet &cstr) {
  auto index = dyn_cast<BlockArgument>(value);
  if (!index || indices.empty() || index.getOwner() != indices.front().getOwner() ||
      index.getArgNumber() >= indices.size())
    return;
  cstr.bound(value) >= 0;
  cstr.bound(value) < extent(index.getArgNumber());
}

} // namespace idr::arrays

using namespace idr::arrays;

//===----------------------------------------------------------------------===//
// idr.transpose
//===----------------------------------------------------------------------===//

LogicalResult TransposeOp::verify() {
  auto from = getInput().getType();
  auto to = getResult().getType();
  ArrayRef<int64_t> permutation = getPermutation();
  if (from.getElementType() != to.getElementType() || from.getRank() != to.getRank() ||
      permutation.size() != static_cast<size_t>(to.getRank()) || !isPermutationVector(permutation))
    return emitOpError("takes ") << from << " to " << to << " by " << permutation
                                 << ", which is no permutation of its dimensions";
  for (auto [d, from_d] : llvm::enumerate(permutation)) {
    int64_t a = to.getDimSize(static_cast<unsigned>(d));
    int64_t b = from.getDimSize(static_cast<unsigned>(from_d));
    if (!ShapedType::isDynamic(a) && !ShapedType::isDynamic(b) && a != b)
      return emitOpError("gives dimension ") << d << " the size " << a << " of a dimension of "
                                             << b;
  }
  return success();
}

// The identity is its input; a transpose of a transpose that undoes it, the
// first one's input.
OpFoldResult TransposeOp::fold(FoldAdaptor) {
  ArrayRef<int64_t> permutation = getPermutation();
  if (isIdentityPermutation(permutation) && getInput().getType() == getType())
    return getInput();
  auto inner = getInput().getDefiningOp<TransposeOp>();
  if (!inner || inner.getInput().getType() != getType() ||
      !llvm::equal(invertPermutationVector(inner.getPermutation()), permutation))
    return {};
  return inner.getInput();
}

// A new array of the input's elements.
void TransposeOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(elementsOf(getInput()), elementsOf(getResult()));
  edges.fresh(getResult());
}

LogicalResult TransposeOp::reifyResultShapes(OpBuilder &b, ReifiedRankedShapedTypeDims &shapes) {
  shapes.push_back(applyPermutation(tensor::getMixedSizes(b, getLoc(), getInput()),
                                    getPermutation()));
  return success();
}

void TransposeOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                  ValueBoundsConstraintSet &cstr) {
  cstr.bound(value)[dim] ==
      cstr.getExpr(getInput(), getPermutation()[static_cast<size_t>(dim)]);
}

//===----------------------------------------------------------------------===//
// idr.array.yield
//===----------------------------------------------------------------------===//

// The world of a tabulation in the world's order goes on to the next step
// and out; the values after an update's element go out. Nothing else is
// forwarded: an element goes into an array, which is no successor's input.
MutableOperandRange ArrayYieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  Operation *parent = (*this)->getParentOp();
  auto count = static_cast<unsigned>(getValues().size());
  if (count == 0)
    return MutableOperandRange(*this, 0, 0);
  return TypeSwitch<Operation *, MutableOperandRange>(parent)
      .Case<TabulateOp, FoldLastOp, ScanLastOp>(
          [&](Operation *) { return MutableOperandRange(*this, 0, 0); })
      .Case([&](TabulateIOOp) { return MutableOperandRange(*this, count - 1, 1); })
      .Case([&](UpdateOpInterface) { return MutableOperandRange(*this, 1, count - 1); })
      .DefaultUnreachable("idr.array.yield ends a region of no array op");
}

// Each element or cell moves in at its index of the array its position
// names: the j-th array a tabulation or a scan makes, the j-th result of a
// fold, the array or buffer an update writes, which takes the first value
// alone. A world goes on, and what an update gives out leaves it, each
// forwarded (RegionBranchOpInterface).
void ArrayYieldOp::getFlowEdges(FlowEdges &edges) {
  auto into = [&](ValueRange arrays) {
    for (auto [at, array] : llvm::enumerate(arrays))
      if (at < getValues().size())
        edges.flow(atIndex(getValuesMutable()[static_cast<unsigned>(at)]), elementsOf(array));
  };
  TypeSwitch<Operation *>((*this)->getParentOp())
      .Case([&](TabulateOp op) { into(op.getArrays()); })
      .Case([&](TabulateIOOp op) { into(op.getArrays()); })
      .Case([&](FoldLastOp op) { into(op.getResults()); })
      .Case([&](ScanLastOp op) { into(op.getResults()); })
      .Case([&](UpdateOpInterface op) { into(op.getArray()); })
      .DefaultUnreachable("idr.array.yield ends a region of no array op");
}
