// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The folds and scans along the last dimension, idr.array.fold_last and
// idr.array.scan_last, and the yield that ends every region of the
// generating set; the rules they share with the tabulation are
// idr/IR/Arrays.h's.
//
// A fold and a scan are destination-style, as upstream's structured ops
// are: on tensors each result is its destination with the region's values
// written in, on buffers the op writes its destinations and gives nothing.
// For each index of the frame a fold folds from what its destination holds
// there and leaves the last accumulator in its place; a scan reads its
// first accumulators from its inputs and writes every accumulator into its
// destination. On buffers each is its loops, made by upstream's
// lowerToLoopsUsingSCFForOp from the three tiling methods each implements,
// in row-major order, the last axis fastest; every other tiling method
// keeps its failing default, so nothing retiles an order the program can
// observe.

#include "idr/IR/Arrays.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

using namespace mlir;
using namespace idr;
using namespace idr::arrays;

namespace {

// A fold's or a scan's destinations or inputs, of which ODS has checked
// there is one: all sharing their `frame` leading dimensions, and an
// accumulator each, its element or cell there, and every one a tensor or
// every one a buffer.
LogicalResult verifyAccumulators(Operation *op, ValueRange arrays, unsigned frame,
                                 Block::BlockArgListType accumulators) {
  if (accumulators.size() != arrays.size())
    return op->emitOpError("binds ") << accumulators.size() << " accumulators for "
                                     << arrays.size() << " arrays";
  auto first = cast<ShapedType>(arrays.front().getType());
  for (auto [array, accumulator] : llvm::zip_equal(arrays, accumulators)) {
    auto type = cast<ShapedType>(array.getType());
    if (!sameLead(first, type, frame))
      return op->emitOpError("folds ") << type << ", whose frame of " << frame
                                       << " dimensions is not that of " << first;
    if (accumulator.getType() != cellOf(type, frame))
      return op->emitOpError("binds an accumulator of ")
             << accumulator.getType() << " for an array of " << type;
  }
  return success();
}

// An op on tensors or an op on buffers, never one on both: its results are
// its destinations written, or it writes them.
LogicalResult verifyOneForm(DestinationStyleOpInterface op) {
  if (op.hasPureTensorSemantics() || op.hasPureBufferSemantics())
    return success();
  return op->emitOpError("writes tensors and buffers in one op");
}

// What a step of a fold or a scan on buffers reads and gives, at the
// frame's index `frame` and the step `step`.
SmallVector<Value> stepArgs(ValueRange frame, Value step, ValueRange accumulators) {
  SmallVector<Value> args(frame);
  args.push_back(step);
  llvm::append_range(args, accumulators);
  return args;
}

} // namespace

//===----------------------------------------------------------------------===//
// idr.array.fold_last
//===----------------------------------------------------------------------===//

MutableOperandRange ArrayFoldLastOp::getDpsInitsMutable() { return getInitsMutable(); }

unsigned ArrayFoldLastOp::getFrameRank() { return getRank() - 1; }

unsigned ArrayFoldLastOp::getRank() {
  return getBody()->getNumArguments() - static_cast<unsigned>(getInits().size());
}

Block::BlockArgListType ArrayFoldLastOp::getAccumulators() {
  return getBody()->getArguments().drop_front(getRank());
}

LogicalResult ArrayFoldLastOp::verify() {
  if (getBody()->getNumArguments() <= getInits().size())
    return emitOpError("binds no index of the fold before its accumulators");
  if (failed(verifyOneForm(*this)) || failed(verifyIndices(*this, getRank())))
    return failure();
  return verifyAccumulators(*this, getInits(), getFrameRank(), getAccumulators());
}

LogicalResult ArrayFoldLastOp::verifyRegions() {
  return verifyEnd(*this, ValueRange(getAccumulators()).getTypes());
}

void ArrayFoldLastOp::getSuccessorRegions(RegionBranchPoint,
                                          SmallVectorImpl<RegionSuccessor> &regions) {
  generatingSuccessors(*this, regions);
}

SmallVector<utils::IteratorType> ArrayFoldLastOp::getLoopIteratorTypes() {
  return iteratorsOf(*this, getRank(), getFrameRank());
}

SmallVector<Range> ArrayFoldLastOp::getIterationDomain(OpBuilder &b) {
  return domainOf(b, *this, getRank());
}

// At the frame's index, each accumulator is taken out of its destination,
// the region runs with it, and the next is put back where it was.
LogicalResult ArrayFoldLastOp::generateScalarImplementation(OpBuilder &b, Location loc,
                                                       ValueRange ivs) {
  if (!hasPureBufferSemantics())
    return emitOpError("is made loops on tensors, which it writes in no order");
  ValueRange frame = ivs.take_front(getFrameRank());
  SmallVector<Value> accumulators = llvm::map_to_vector(
      getInits(), [&](Value init) { return takeAt(b, loc, init, frame); });
  cloneStep(b, loc, getRegion(), stepArgs(frame, ivs.back(), accumulators),
            [&](OpBuilder &at, ValueRange next) {
              for (auto [value, init] : llvm::zip_equal(next, getInits()))
                putBackAt(at, loc, value, init, frame);
            });
  return success();
}

// A tensor result is its destination with the last accumulators written at
// the frame's indices; every accumulator is first what its destination
// holds there, then what the step before gave, which the yield moves in.
void ArrayFoldLastOp::getFlowEdges(FlowEdges &edges) {
  for (auto [init, result] : llvm::zip_equal(getInitsMutable(), getResults()))
    edges.flow(FlowSource::of(init), FlowPlace::of(result));
  for (auto [init, accumulator] : llvm::zip_equal(getInits(), getAccumulators()))
    edges.flow(FlowSource::partOf(init, elementsOf(init)), atIndex(accumulator));
}

ValueRange ArrayFoldLastOp::getYieldTargets() {
  return hasPureTensorSemantics() ? ValueRange(getResults()) : ValueRange(getInits());
}

LogicalResult ArrayFoldLastOp::reifyResultShapes(OpBuilder &b,
                                                 ReifiedRankedShapedTypeDims &shapes) {
  for (Value init : getInits())
    shapes.push_back(tensor::getMixedSizes(b, getLoc(), init));
  return success();
}

void ArrayFoldLastOp::populateBoundsForIndexValue(Value value, ValueBoundsConstraintSet &cstr) {
  boundIndex(*this, value, getBody()->getArguments().take_front(getRank()), cstr);
}

// A result is shaped as its destination.
void ArrayFoldLastOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                 ValueBoundsConstraintSet &cstr) {
  unsigned at = cast<OpResult>(value).getResultNumber();
  cstr.bound(value)[dim] == cstr.getExpr(getInits()[at], dim);
}

Speculation::Speculatability ArrayFoldLastOp::getSpeculatability() {
  return hasPureTensorSemantics() ? Speculation::RecursivelySpeculatable
                                  : Speculation::NotSpeculatable;
}

//===----------------------------------------------------------------------===//
// idr.array.scan_last
//===----------------------------------------------------------------------===//

MutableOperandRange ArrayScanLastOp::getDpsInitsMutable() { return getOutsMutable(); }

unsigned ArrayScanLastOp::getFrameRank() { return getRank() - 1; }

unsigned ArrayScanLastOp::getRank() {
  return getBody()->getNumArguments() - static_cast<unsigned>(getInits().size());
}

Block::BlockArgListType ArrayScanLastOp::getAccumulators() {
  return getBody()->getArguments().drop_front(getRank());
}

LogicalResult ArrayScanLastOp::verify() {
  if (getBody()->getNumArguments() <= getInits().size())
    return emitOpError("binds no index of the scan before its accumulators");
  if (failed(verifyOneForm(*this)) || failed(verifyIndices(*this, getRank())) ||
      failed(verifyAccumulators(*this, getInits(), getFrameRank(), getAccumulators())))
    return failure();
  if (getOuts().size() != getInits().size())
    return emitOpError("writes ") << getOuts().size() << " arrays for " << getInits().size()
                                  << " inputs";
  unsigned frame = getFrameRank();
  std::optional<int64_t> length = getConstantIntValue(getLength());
  for (auto [init, out] : llvm::zip_equal(getInits().getTypes(), getOuts().getTypes())) {
    auto from = cast<ShapedType>(init);
    auto to = cast<ShapedType>(out);
    bool shaped = to.getElementType() == from.getElementType() &&
                  to.getRank() == from.getRank() + 1 &&
                  to.getShape().take_front(frame) == from.getShape().take_front(frame) &&
                  to.getShape().drop_front(frame + 1) == from.getShape().drop_front(frame);
    if (!shaped)
      return emitOpError("writes ") << to << " for an input of " << from << " and a frame of "
                                    << frame << " dimensions";
    if (length && !to.isDynamicDim(frame) && to.getDimSize(frame) != *length)
      return emitOpError("writes ") << to << " for a scan " << *length << " long";
  }
  return verifyFresh(*this);
}

LogicalResult ArrayScanLastOp::verifyRegions() {
  return verifyEnd(*this, ValueRange(getAccumulators()).getTypes());
}

void ArrayScanLastOp::getSuccessorRegions(RegionBranchPoint,
                                          SmallVectorImpl<RegionSuccessor> &regions) {
  generatingSuccessors(*this, regions);
}

SmallVector<utils::IteratorType> ArrayScanLastOp::getLoopIteratorTypes() {
  return iteratorsOf(*this, getRank(), getFrameRank());
}

// Every destination has the frame's dimensions, then the scan's.
SmallVector<Range> ArrayScanLastOp::getIterationDomain(OpBuilder &b) {
  return domainOf(b, *this, getRank());
}

// At the frame's index and a step, each accumulator is a copy of what the
// input holds at the frame's index for the first step, else of what the
// step before wrote, which both keep; the next is placed at the step.
LogicalResult ArrayScanLastOp::generateScalarImplementation(OpBuilder &b, Location loc,
                                                       ValueRange ivs) {
  if (!hasPureBufferSemantics())
    return emitOpError("is made loops on tensors, which it writes in no order");
  ValueRange frame = ivs.take_front(getFrameRank());
  Value step = ivs.back();
  Value zero = arith::ConstantIndexOp::create(b, loc, 0);
  Value first = arith::CmpIOp::create(b, loc, arith::CmpIPredicate::eq, step, zero);
  auto read = scf::IfOp::create(
      b, loc, first,
      [&](OpBuilder &at, Location l) {
        SmallVector<Value> copies = llvm::map_to_vector(
            getInits(), [&](Value init) { return copyAt(at, l, init, frame); });
        scf::YieldOp::create(at, l, copies);
      },
      [&](OpBuilder &at, Location l) {
        Value one = arith::ConstantIndexOp::create(at, l, 1);
        SmallVector<Value> before(frame);
        before.push_back(arith::SubIOp::create(at, l, step, one));
        SmallVector<Value> copies = llvm::map_to_vector(
            getOuts(), [&](Value out) { return copyAt(at, l, out, before); });
        scf::YieldOp::create(at, l, copies);
      });
  SmallVector<Value> at(ivs);
  cloneStep(b, loc, getRegion(), stepArgs(frame, step, read.getResults()),
            [&](OpBuilder &here, ValueRange next) {
              for (auto [value, out] : llvm::zip_equal(next, getOuts()))
                placeAt(here, loc, value, out, at);
            });
  return success();
}

// A tensor result is its destination with every accumulator written; an
// accumulator is a copy of what an input or the result holds, which keep
// theirs.
void ArrayScanLastOp::getFlowEdges(FlowEdges &edges) {
  for (auto [out, result] : llvm::zip_equal(getOutsMutable(), getResults()))
    edges.flow(FlowSource::of(out), FlowPlace::of(result));
  for (auto [init, accumulator] : llvm::zip_equal(getInits(), getAccumulators()))
    edges.flow(FlowSource::partOf(init, elementsOf(init)), atIndex(accumulator));
  for (auto [out, accumulator] : llvm::zip_equal(getYieldTargets(), getAccumulators()))
    edges.flow(FlowSource::partOf(out, elementsOf(out)), atIndex(accumulator));
}

ValueRange ArrayScanLastOp::getYieldTargets() {
  return hasPureTensorSemantics() ? ValueRange(getResults()) : ValueRange(getOuts());
}

LogicalResult ArrayScanLastOp::reifyResultShapes(OpBuilder &b,
                                                 ReifiedRankedShapedTypeDims &shapes) {
  for (Value out : getOuts())
    shapes.push_back(tensor::getMixedSizes(b, getLoc(), out));
  return success();
}

void ArrayScanLastOp::populateBoundsForIndexValue(Value value, ValueBoundsConstraintSet &cstr) {
  boundIndex(*this, value, getBody()->getArguments().take_front(getRank()), cstr);
}

void ArrayScanLastOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                 ValueBoundsConstraintSet &cstr) {
  unsigned at = cast<OpResult>(value).getResultNumber();
  cstr.bound(value)[dim] == cstr.getExpr(getOuts()[at], dim);
}

Speculation::Speculatability ArrayScanLastOp::getSpeculatability() {
  return hasPureTensorSemantics() ? Speculation::RecursivelySpeculatable
                                  : Speculation::NotSpeculatable;
}

//===----------------------------------------------------------------------===//
// idr.array.yield
//===----------------------------------------------------------------------===//

// What a step gives goes into memory, never to a successor: nothing is
// forwarded.
MutableOperandRange ArrayYieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  return MutableOperandRange(*this, 0, 0);
}

// The j-th value moves into the j-th array its parent writes, at the step's
// index: an element, or the elements of a cell.
void ArrayYieldOp::getFlowEdges(FlowEdges &edges) {
  ValueRange targets = cast<YieldTargetsOpInterface>((*this)->getParentOp()).getYieldTargets();
  for (auto [value, target] : llvm::zip_equal(getValuesMutable(), targets))
    edges.flow(atIndex(value), FlowPlace::partOf(target, elementsOf(target)));
}
