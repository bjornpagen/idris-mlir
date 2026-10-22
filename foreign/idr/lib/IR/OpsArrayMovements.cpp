// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The three movements a step of a generating op on buffers makes (take,
// copy, place), each of what the slots under its indices hold, and their
// builders, which every step's loops call (idr/IR/Arrays.h); and the copy
// that first writes a buffer allocated for it, which places its slots and
// releases none.

#include "idr/IR/Arrays.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/TypeUtilities.h"

using namespace mlir;
using namespace idr;
using namespace idr::arrays;

namespace {

// A movement at `indices` of a buffer moves what its slots there hold: an
// element at as many indices as the buffer has dimensions, else the cell
// under them, a buffer of the identity layout.
LogicalResult verifyMoved(Operation *op, Type moved, MemRefType buffer, size_t indices) {
  if (indices > static_cast<size_t>(buffer.getRank()))
    return op->emitOpError("takes ") << indices << " indices for a buffer of rank "
                                     << buffer.getRank();
  Type expected = cellOf(buffer, static_cast<unsigned>(indices));
  if (moved != expected)
    return op->emitOpError("moves ") << moved << " where the buffer holds " << expected
                                     << " at " << indices << " indices";
  return success();
}

} // namespace

//===----------------------------------------------------------------------===//
// The movements of a step on buffers
//===----------------------------------------------------------------------===//

LogicalResult ArrayTakeOp::verify() {
  return verifyMoved(*this, getValue().getType(), cast<MemRefType>(getBuffer().getType()),
                     getIndices().size());
}

LogicalResult ArrayCopyOp::verify() {
  return verifyMoved(*this, getValue().getType(), cast<MemRefType>(getBuffer().getType()),
                     getIndices().size());
}

LogicalResult ArrayPlaceOp::verify() {
  return verifyMoved(*this, getValue().getType(), cast<MemRefType>(getBuffer().getType()),
                     getIndices().size());
}

// A take moves what the slots hold out, which leaves them holding nothing;
// a copy reads it with references of its own; a place moves a value in.
void ArrayTakeOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(elementsOf(getBuffer()), atIndex(getValue()));
  edges.overwrite(elementsOf(getBuffer()));
}
void ArrayCopyOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(elementsOf(getBuffer()), atIndex(getValue()));
  edges.fresh(getValue());
}
void ArrayPlaceOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(atIndex(getValueMutable()), elementsOf(getBuffer()));
}

namespace idr::arrays {

Value takeAt(OpBuilder &b, Location loc, Value buffer, ValueRange indices) {
  auto type = cast<MemRefType>(buffer.getType());
  return ArrayTakeOp::create(b, loc, cellOf(type, static_cast<unsigned>(indices.size())), buffer,
                             indices);
}

Value copyAt(OpBuilder &b, Location loc, Value buffer, ValueRange indices) {
  auto type = cast<MemRefType>(buffer.getType());
  return ArrayCopyOp::create(b, loc, cellOf(type, static_cast<unsigned>(indices.size())), buffer,
                             indices);
}

void placeAt(OpBuilder &b, Location loc, Value value, Value buffer, ValueRange indices) {
  ArrayPlaceOp::create(b, loc, value, buffer, indices);
}

} // namespace idr::arrays

//===----------------------------------------------------------------------===//
// A fresh buffer's first write
//===----------------------------------------------------------------------===//

// The target is the copy's destination, which it writes whole.
MutableOperandRange ArrayPlaceCopyOp::getDpsInitsMutable() { return getTargetMutable(); }

// The target is a buffer allocated for the copy, which nothing wrote: the
// copy places its slots, releasing none, so a target that held elements
// would keep their references for ever. The source is any view of an array
// of the target's shape and element.
LogicalResult ArrayPlaceCopyOp::verify() {
  if (!arrays::allocationOf(getTarget()))
    return emitOpError("places a copy in ") << getTarget().getType()
                                            << ", which is no buffer allocated for it";
  auto from = cast<MemRefType>(unrestricted(getSource().getType()));
  auto to = cast<MemRefType>(unrestricted(getTarget().getType()));
  if (from.getElementType() != to.getElementType() ||
      failed(verifyCompatibleShape(from.getShape(), to.getShape())))
    return emitOpError("copies ") << from << " into " << to << ", of another shape or element";
  return success();
}

// Each element the source holds is placed in the target, with a reference
// of its own; the source keeps its own, and the target held nothing.
void ArrayPlaceCopyOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(elementsOf(getSource()), elementsOf(getTarget()));
}
