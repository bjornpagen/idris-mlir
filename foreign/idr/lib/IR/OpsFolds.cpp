// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The folds and scans along the last dimension, idr.fold_last and
// idr.scan_last: for each index of a frame, a left fold from its init's
// element or cell; their rules, shapes, control flow and how an
// accumulator moves.

#include "idr/IR/Arrays.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"

using namespace mlir;
using namespace idr;
using namespace idr::arrays;

namespace {

// A fold's or a scan's inits, of which ODS has checked there is one: all
// sharing their `frame` leading dimensions, and an accumulator each, its
// element or cell there.
LogicalResult verifyInits(Operation *op, TypeRange inits, unsigned frame,
                          Block::BlockArgListType accumulators) {
  if (accumulators.size() != inits.size())
    return op->emitOpError("binds ") << accumulators.size() << " accumulators for "
                                     << inits.size() << " inits";
  auto first = cast<RankedTensorType>(inits.front());
  for (auto [init, accumulator] : llvm::zip_equal(inits, accumulators)) {
    auto type = cast<RankedTensorType>(init);
    if (!sameLead(first, type, frame))
      return op->emitOpError("folds ") << type << ", whose frame of " << frame
                                       << " dimensions is not that of " << first;
    if (accumulator.getType() != cellOf(type, frame))
      return op->emitOpError("binds an accumulator of ")
             << accumulator.getType() << " for an init of " << type;
  }
  return success();
}

// Where a fold's or a scan's accumulators come from: each starts as what
// its init holds at the frame's index, and each next one is what the step
// before wrote into the result, from which the yield's edge leads.
void accumulatorEdges(ValueRange inits, ValueRange results, Block::BlockArgListType accumulators,
                      FlowEdges &edges) {
  for (auto [init, result, accumulator] : llvm::zip_equal(inits, results, accumulators)) {
    edges.flow(elementsOf(init), atIndex(accumulator));
    edges.flow(elementsOf(result), atIndex(accumulator));
  }
}

// The size of dimension `dim` of a fold's or a scan's domain: the length
// along its last dimension, else the inits' own dimension there. Both are
// read from where the op holds them, made with `b`, or named for value
// bounds.
template <typename OpT>
OpFoldResult foldExtent(OpT op, OpBuilder &b, unsigned dim) {
  if (dim == op.getFrameRank())
    return op.getLength();
  return tensor::getMixedSize(b, op.getLoc(), op.getInits().front(), dim);
}
template <typename OpT>
ValueBoundsConstraintSet::Variable foldExtentBound(OpT op, unsigned dim) {
  if (dim == op.getFrameRank())
    return op.getLength();
  return {op.getInits().front(), static_cast<int64_t>(dim)};
}

} // namespace

//===----------------------------------------------------------------------===//
// idr.fold_last
//===----------------------------------------------------------------------===//

LogicalResult FoldLastOp::verify() {
  if (getBody()->getNumArguments() <= getInits().size())
    return emitOpError("binds no index of the fold before its accumulators");
  if (failed(verifyIndices(*this, getRank())) ||
      failed(verifyInits(*this, getInits().getTypes(), getFrameRank(), getAccumulators())))
    return failure();
  if (getResults().getTypes() != getInits().getTypes())
    return emitOpError("gives ") << getResults().getTypes() << " for inits of "
                                 << getInits().getTypes();
  return success();
}

LogicalResult FoldLastOp::verifyRegions() {
  return verifyEnd(*this, ValueRange(getAccumulators()).getTypes());
}

SmallVector<Iteration> FoldLastOp::getIterations() {
  SmallVector<Iteration> iterations(getFrameRank(), Iteration::Parallel);
  iterations.push_back(Iteration::Ordered);
  return iterations;
}

OpFoldResult FoldLastOp::getExtent(OpBuilder &b, unsigned dim) {
  return foldExtent(*this, b, dim);
}

ValueBoundsConstraintSet::Variable FoldLastOp::getExtentBound(unsigned dim) {
  return foldExtentBound(*this, dim);
}

void FoldLastOp::getSuccessorRegions(RegionBranchPoint, SmallVectorImpl<RegionSuccessor> &regions) {
  generatingSuccessors(*this, regions);
}

// Each result is its init with the last accumulators written at the
// frame's indices.
void FoldLastOp::getFlowEdges(FlowEdges &edges) {
  for (auto [init, result] : llvm::zip_equal(getInits(), getResults()))
    edges.flow(FlowPoint::of(init), FlowPoint::of(result));
  accumulatorEdges(getInits(), getResults(), getAccumulators(), edges);
}

LogicalResult FoldLastOp::reifyResultShapes(OpBuilder &b, ReifiedRankedShapedTypeDims &shapes) {
  for (Value init : getInits())
    shapes.push_back(tensor::getMixedSizes(b, getLoc(), init));
  return success();
}

FailureOr<OpFoldResult> FoldLastOp::reifyDimOfResult(OpBuilder &b, int result, int dim) {
  return tensor::getMixedSize(b, getLoc(), getInits()[static_cast<unsigned>(result)], dim);
}

void FoldLastOp::populateBoundsForIndexValue(Value value, ValueBoundsConstraintSet &cstr) {
  boundIndex(value, getIndices(),
             [&](unsigned dim) {
               return dim == getFrameRank() ? cstr.getExpr(getLength())
                                            : cstr.getExpr(getInits().front(), dim);
             },
             cstr);
}

// A result is shaped as its init.
void FoldLastOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                 ValueBoundsConstraintSet &cstr) {
  unsigned at = cast<OpResult>(value).getResultNumber();
  cstr.bound(value)[dim] == cstr.getExpr(getInits()[at], dim);
}

//===----------------------------------------------------------------------===//
// idr.scan_last
//===----------------------------------------------------------------------===//

LogicalResult ScanLastOp::verify() {
  if (getBody()->getNumArguments() <= getInits().size())
    return emitOpError("binds no index of the scan before its accumulators");
  if (failed(verifyIndices(*this, getRank())) ||
      failed(verifyInits(*this, getInits().getTypes(), getFrameRank(), getAccumulators())))
    return failure();
  if (getResults().size() != getInits().size())
    return emitOpError("gives ") << getResults().size() << " arrays for " << getInits().size()
                                 << " inits";
  unsigned frame = getFrameRank();
  std::optional<int64_t> length = getConstantIntValue(getLength());
  for (auto [init, result] : llvm::zip_equal(getInits().getTypes(), getResults().getTypes())) {
    auto from = cast<RankedTensorType>(init);
    auto to = cast<RankedTensorType>(result);
    bool shaped = to.getElementType() == from.getElementType() &&
                  to.getRank() == from.getRank() + 1 &&
                  to.getShape().take_front(frame) == from.getShape().take_front(frame) &&
                  to.getShape().drop_front(frame + 1) == from.getShape().drop_front(frame);
    if (!shaped)
      return emitOpError("gives ") << to << " for an init of " << from << " and a frame of "
                                   << frame << " dimensions";
    if (length && !to.isDynamicDim(frame) && to.getDimSize(frame) != *length)
      return emitOpError("gives ") << to << " for a scan " << *length << " long";
  }
  return success();
}

LogicalResult ScanLastOp::verifyRegions() {
  return verifyEnd(*this, ValueRange(getAccumulators()).getTypes());
}

SmallVector<Iteration> ScanLastOp::getIterations() {
  SmallVector<Iteration> iterations(getFrameRank(), Iteration::Parallel);
  iterations.push_back(Iteration::Ordered);
  return iterations;
}

OpFoldResult ScanLastOp::getExtent(OpBuilder &b, unsigned dim) {
  return foldExtent(*this, b, dim);
}

ValueBoundsConstraintSet::Variable ScanLastOp::getExtentBound(unsigned dim) {
  return foldExtentBound(*this, dim);
}

void ScanLastOp::getSuccessorRegions(RegionBranchPoint, SmallVectorImpl<RegionSuccessor> &regions) {
  generatingSuccessors(*this, regions);
}

// Each result is a new array of every accumulator.
void ScanLastOp::getFlowEdges(FlowEdges &edges) {
  for (Value result : getResults())
    edges.fresh(result);
  accumulatorEdges(getInits(), getResults(), getAccumulators(), edges);
}

// A result's dimensions are its init's frame, the length, then its init's
// cell.
LogicalResult ScanLastOp::reifyResultShapes(OpBuilder &b, ReifiedRankedShapedTypeDims &shapes) {
  for (Value init : getInits()) {
    SmallVector<OpFoldResult> dims = tensor::getMixedSizes(b, getLoc(), init);
    dims.insert(dims.begin() + getFrameRank(), OpFoldResult(getLength()));
    shapes.push_back(std::move(dims));
  }
  return success();
}

FailureOr<OpFoldResult> ScanLastOp::reifyDimOfResult(OpBuilder &b, int result, int dim) {
  auto frame = static_cast<int>(getFrameRank());
  if (dim == frame)
    return OpFoldResult(getLength());
  return tensor::getMixedSize(b, getLoc(), getInits()[static_cast<unsigned>(result)],
                              dim < frame ? dim : dim - 1);
}

void ScanLastOp::populateBoundsForIndexValue(Value value, ValueBoundsConstraintSet &cstr) {
  boundIndex(value, getIndices(),
             [&](unsigned dim) {
               return dim == getFrameRank() ? cstr.getExpr(getLength())
                                            : cstr.getExpr(getInits().front(), dim);
             },
             cstr);
}

void ScanLastOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                 ValueBoundsConstraintSet &cstr) {
  Value init = getInits()[cast<OpResult>(value).getResultNumber()];
  auto frame = static_cast<int64_t>(getFrameRank());
  if (dim == frame)
    cstr.bound(value)[dim] == cstr.getExpr(getLength());
  else
    cstr.bound(value)[dim] == cstr.getExpr(init, dim < frame ? dim : dim - 1);
}
