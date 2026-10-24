// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops on mutable memory (new, get, set, update), with their rules,
// shapes and how an element moves; the reads of a value array, of an
// element and of an extent, that give the array back; and the opening of
// the buffer a field holds as the array it is.
//
// Mutable memory is base's IOArray, Buffer and IORef: a buffer in the
// memory space #idr.mutable, written after it is shared. A value array's
// buffer, which bufferization makes of a tensor, is in the default memory
// space and written only where One-Shot proved the write in place, so no
// type is both. Every access takes one `index` per dimension, as
// upstream's memref ops do.

#include "idr/IR/Arrays.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Utils/StaticValueUtils.h"

using namespace mlir;
using namespace idr;
using namespace idr::arrays;

namespace {

// An access takes one index per dimension of its buffer, and a new array
// one size: what memref.load and memref.alloc ask of theirs.
LogicalResult verifyCount(Operation *op, size_t count, StringRef what, MemRefType array) {
  if (count != static_cast<size_t>(array.getRank()))
    return op->emitOpError("takes ") << count << " " << what << " for an array of rank "
                                     << array.getRank();
  return success();
}

// An element moves into a buffer, or out of it, at the buffer's element
// type, the grade it carries aside.
LogicalResult verifyElement(Operation *op, StringRef what, Type type, MemRefType array) {
  if (unrestricted(type) != array.getElementType())
    return op->emitOpError() << what << " has type " << type << ", but the array holds "
                             << array.getElementType();
  return success();
}

} // namespace

namespace idr {

// A value array's buffer is in the default memory space, which no mutable
// memory is in.
bool isValueBuffer(Type type) {
  auto buffer = dyn_cast<MemRefType>(unrestricted(type));
  return buffer && !buffer.getMemorySpace();
}

} // namespace idr

//===----------------------------------------------------------------------===//
// Mutable memory
//===----------------------------------------------------------------------===//

LogicalResult ArrayNewOp::verify() {
  auto type = cast<MemRefType>(unrestricted(getArray().getType()));
  if (failed(verifyCount(*this, getSizes().size(), "sizes", type)))
    return failure();
  return verifyElement(*this, "the fill", getFill().getType(), type);
}

LogicalResult ArrayGetOp::verify() {
  auto type = cast<MemRefType>(unrestricted(getArray().getType()));
  if (failed(verifyCount(*this, getIndices().size(), "indices", type)))
    return failure();
  return verifyElement(*this, "the result", getValue().getType(), type);
}

LogicalResult ArraySetOp::verify() {
  auto type = cast<MemRefType>(unrestricted(getArray().getType()));
  if (failed(verifyCount(*this, getIndices().size(), "indices", type)))
    return failure();
  return verifyElement(*this, "the value", getValue().getType(), type);
}

// Each dimension of the new array is its size: the frontend gives a size
// below zero as zero before it is an index.
LogicalResult ArrayNewOp::reifyResultShapes(OpBuilder &, ReifiedRankedShapedTypeDims &shapes) {
  shapes.push_back(getAsOpFoldResult(getSizes()));
  return success();
}

// An element moves in through the fill, which every element holds, and
// through a write, which releases the element it replaces; a read borrows
// it, the reference a reader keeps being counting's to take.
void ArrayNewOp::getFlowEdges(FlowEdges &edges) {
  everyElementEdges(getFillMutable(), getArray(), edges);
  edges.fresh(getArray());
}
void ArrayGetOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowSource::partOf(getArray(), elementsOf(getArray())), FlowPlace::of(getValue()));
}
void ArraySetOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowSource::of(getValueMutable()),
             FlowPlace::partOf(getArray(), elementsOf(getArray())));
  edges.overwrite(getArray(), elementsOf(getArray()));
}

//===----------------------------------------------------------------------===//
// idr.array.update
//===----------------------------------------------------------------------===//

// One index per dimension of the buffer, and a region that binds the
// element alone, at the buffer's element type at any grade.
LogicalResult ArrayUpdateOp::verify() {
  auto type = cast<MemRefType>(unrestricted(getArray().getType()));
  if (failed(verifyCount(*this, getIndices().size(), "indices", type)))
    return failure();
  Block &body = getRegion().front();
  if (body.getNumArguments() != 1)
    return emitOpError("binds ") << body.getNumArguments()
                                 << " values in its region, where it binds the element alone";
  return verifyElement(*this, "the element", body.getArgument(0).getType(), type);
}

// Between the element's move out and its move back, its place holds
// nothing, and only the region runs there. So the region reads and writes
// neither the contents nor a state above them, where any access that could
// see the empty place falls, whichever value it names; counting's own work
// there (a cell filled, beneath the contents, and what it frees or
// allocates on the heap) passes. Asked of the region's effects, its calls'
// rows among them.
LogicalResult ArrayUpdateOp::verifyRegions() {
  if (auto end = dyn_cast<ArrayUpdateYieldOp>(getRegion().front().getTerminator())) {
    auto type = cast<MemRefType>(unrestricted(getArray().getType()));
    if (unrestricted(end.getElement().getType()) != type.getElementType())
      return end.emitOpError("gives back ") << end.getElement().getType()
                                            << " for an element of " << type.getElementType();
    if (end.getOuts().getTypes() != getOuts().getTypes())
      return end.emitOpError("gives ") << end.getOuts().getTypes() << " where the update gives "
                                       << getOuts().getTypes();
  }
  for (Operation &inner : getRegion().front().without_terminator())
    if (touchesInPlace(&inner))
      return inner.emitOpError(
          "may read or write the contents, or a state above them, inside an update's region");
  return success();
}

void ArrayUpdateOp::getSuccessorRegions(RegionBranchPoint point,
                                        SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent())
    regions.push_back(RegionSuccessor(&getRegion()));
  else
    regions.push_back(RegionSuccessor(getOperation()));
}

ValueRange ArrayUpdateOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getOuts();
  return ValueRange();
}

void ArrayUpdateOp::getRegionInvocationBounds(ArrayRef<Attribute>,
                                              SmallVectorImpl<InvocationBounds> &bounds) {
  bounds.emplace_back(1, 1);
}

// The element moves out of its place into the region with the reference
// its place held, the place left empty until the region's end moves the
// rebuilt one back in, as the take a split update becomes declares. So the
// element holds a reference of its own, which its region moves on or gives
// up, never a view of the array.
void ArrayUpdateOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowSource::partOf(getArray(), elementsOf(getArray())),
             FlowPlace::of(getRegion().front().getArgument(0)));
  edges.overwrite(getArray(), elementsOf(getArray()));
}

ValueRange ArrayUpdateOp::getYieldTargets() { return getODSOperands(0); }

// The values after the element leave the update as its results.
MutableOperandRange ArrayUpdateYieldOp::getMutableSuccessorOperands(RegionSuccessor) {
  return getOutsMutable();
}

// The rebuilt element moves back into the place its update emptied.
void ArrayUpdateYieldOp::getFlowEdges(FlowEdges &edges) {
  auto update = cast<ArrayUpdateOp>((*this)->getParentOp());
  edges.flow(FlowSource::of(getElementMutable()),
             FlowPlace::partOf(update.getArray(), elementsOf(update.getArray())));
}

//===----------------------------------------------------------------------===//
// idr.array.read
//===----------------------------------------------------------------------===//

// One index per dimension.
LogicalResult ArrayReadOp::verify() {
  auto type = cast<RankedTensorType>(getArray().getType());
  if (getIndices().size() != static_cast<size_t>(type.getRank()))
    return emitOpError("takes ") << getIndices().size() << " indices for an array of rank "
                                 << type.getRank();
  return success();
}

// The array given back is the array; the element is borrowed from it, the
// reference a reader keeps being counting's to take.
void ArrayReadOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowSource::of(getArrayMutable()), FlowPlace::of(getAfter()));
  edges.flow(FlowSource::partOf(getArray(), elementsOf(getArray())), FlowPlace::of(getValue()));
}

//===----------------------------------------------------------------------===//
// idr.array.extent
//===----------------------------------------------------------------------===//

// An axis of the array, and the array given back as it was.
LogicalResult ArrayExtentOp::verify() {
  auto type = cast<RankedTensorType>(getArray().getType());
  if (getAxis() >= static_cast<uint64_t>(type.getRank()))
    return emitOpError("reads axis ") << getAxis() << " of an array of rank " << type.getRank();
  if (getAfter().getType() != type)
    return emitOpError("gives back ") << getAfter().getType() << " for an array of " << type;
  return success();
}

// The array given back is the array; the extent is a new natural, of a
// size no other value holds.
void ArrayExtentOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowSource::of(getArrayMutable()), FlowPlace::of(getAfter()));
  edges.fresh(getExtent());
}

//===----------------------------------------------------------------------===//
// idr.array.open
//===----------------------------------------------------------------------===//

// The array of the buffer the field holds, of its shape and element: the
// field as a read of it gives it, so the array follows its field wherever
// a pass changes the value's type.
LogicalResult ArrayOpenOp::inferReturnTypes(MLIRContext *, std::optional<Location> location,
                                            Adaptor adaptor, SmallVectorImpl<Type> &inferred) {
  Type value = adaptor.getValue().getType();
  std::optional<Type> read = fieldReadType(value, static_cast<unsigned>(adaptor.getIndex()));
  if (!read || !isValueBuffer(*read))
    return emitOptionalError(location, "opens field ", adaptor.getIndex(), " of ", value,
                             ", which holds no value array's buffer");
  auto buffer = cast<MemRefType>(unrestricted(*read));
  inferred.push_back(RankedTensorType::get(buffer.getShape(), buffer.getElementType()));
  return success();
}

// The array is what the field holds; the value it is opened from is only
// read.
void ArrayOpenOp::getFlowEdges(FlowEdges &edges) {
  auto data = cast<DataType>(unrestricted(getValue().getType()));
  auto index = static_cast<unsigned>(getIndex());
  edges.flow(FlowSource::partOf(getValue(), FlowAnchor::fieldOf(data, *data.singleTag(), index)),
             FlowPlace::of(getArray()));
}
