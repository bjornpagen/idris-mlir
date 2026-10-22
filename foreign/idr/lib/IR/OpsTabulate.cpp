// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The tabulation, idr.array.tabulate: each destination written at every
// index of a domain, which is the destinations' leading dimensions, with
// what a region gives there. On tensors its results are its destinations
// written; on buffers it writes them and is its loops, made by upstream's
// lowerToLoopsUsingSCFForOp, in row-major order, the last dimension
// fastest, the region once per index and never on an empty domain. Its
// region's effects order its steps: the effects of IO, which the world
// once ordered, are an order of the region the iterator types state.

#include "idr/IR/Arrays.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"

using namespace mlir;
using namespace idr;
using namespace idr::arrays;

MutableOperandRange ArrayTabulateOp::getDpsInitsMutable() { return getOutsMutable(); }

unsigned ArrayTabulateOp::getRank() { return getBody()->getNumArguments(); }

// What each destination holds at an index of the domain: its element, or
// its cell.
SmallVector<Type> ArrayTabulateOp::getCellTypes() {
  return llvm::map_to_vector(getOuts().getTypes(), [&](Type out) {
    return cellOf(cast<ShapedType>(out), getRank());
  });
}

// The destinations, of which ODS has checked there is one, share the
// domain's dimensions, and are all tensors or all buffers; a destination of
// elements that hold references is fresh, whose every slot the tabulation
// places once.
LogicalResult ArrayTabulateOp::verify() {
  if (!hasPureTensorSemantics() && !hasPureBufferSemantics())
    return emitOpError("writes tensors and buffers in one op");
  if (failed(verifyIndices(*this, getRank())))
    return failure();
  auto first = cast<ShapedType>(getOuts().front().getType());
  for (Value out : getOuts()) {
    auto type = cast<ShapedType>(out.getType());
    if (!sameLead(first, type, getRank()))
      return emitOpError("writes ") << type << ", whose leading " << getRank()
                                    << " dimensions are not those of " << first;
  }
  return verifyFresh(*this);
}

LogicalResult ArrayTabulateOp::verifyRegions() { return verifyEnd(*this, getCellTypes()); }

void ArrayTabulateOp::getSuccessorRegions(RegionBranchPoint,
                                          SmallVectorImpl<RegionSuccessor> &regions) {
  generatingSuccessors(*this, regions);
}

SmallVector<utils::IteratorType> ArrayTabulateOp::getLoopIteratorTypes() {
  return iteratorsOf(*this, getRank(), getRank());
}

SmallVector<Range> ArrayTabulateOp::getIterationDomain(OpBuilder &b) {
  return domainOf(b, *this, getRank());
}

// At an index, the region runs there and each value it gives is placed in
// its destination's slots there, which hold nothing yet.
LogicalResult ArrayTabulateOp::generateScalarImplementation(OpBuilder &b, Location loc,
                                                       ValueRange ivs) {
  if (!hasPureBufferSemantics())
    return emitOpError("is made loops on tensors, which it writes in no order");
  cloneStep(b, loc, getRegion(), ivs, [&](OpBuilder &at, ValueRange given) {
    for (auto [value, out] : llvm::zip_equal(given, getOuts()))
      placeAt(at, loc, value, out, ivs);
  });
  return success();
}

// A tensor result is its destination with each element moved in at its
// index by the yield.
void ArrayTabulateOp::getFlowEdges(FlowEdges &edges) {
  for (auto [out, array] : llvm::zip_equal(getOutsMutable(), getArrays()))
    edges.flow(FlowSource::of(out), FlowPlace::of(array));
}

ValueRange ArrayTabulateOp::getYieldTargets() {
  return hasPureTensorSemantics() ? ValueRange(getArrays()) : ValueRange(getOuts());
}

LogicalResult ArrayTabulateOp::reifyResultShapes(OpBuilder &b,
                                                 ReifiedRankedShapedTypeDims &shapes) {
  for (Value out : getOuts())
    shapes.push_back(tensor::getMixedSizes(b, getLoc(), out));
  return success();
}

void ArrayTabulateOp::populateBoundsForIndexValue(Value value, ValueBoundsConstraintSet &cstr) {
  boundIndex(value, getBody()->getArguments(),
             [&](unsigned dim) { return cstr.getExpr(extentOf(*this, dim)); }, cstr);
}

// A result is shaped as its destination.
void ArrayTabulateOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                 ValueBoundsConstraintSet &cstr) {
  unsigned at = cast<OpResult>(value).getResultNumber();
  cstr.bound(value)[dim] == cstr.getExpr(getOuts()[at], dim);
}

Speculation::Speculatability ArrayTabulateOp::getSpeculatability() {
  return hasPureTensorSemantics() ? Speculation::RecursivelySpeculatable
                                  : Speculation::NotSpeculatable;
}
