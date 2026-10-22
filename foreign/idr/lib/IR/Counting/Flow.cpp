// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How the values of counting's ops move, as data (FlowEdges.h), for the
// ownership markings that read the program while these ops stand in it:
// each op that exists from counting's first step to exclusivity states
// where what it holds, takes or gives goes. A value is followed whole, or
// into and out of a field of another. The ops reuse and the expansion
// make, after every marking has read the program, state nothing.

#include "idr/IR/Flow.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

// A dup is one more reference to what the value reaches.
void CountDupOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowSource::of(getValue()), FlowPlace::of(getResult()));
}

void CountDropOp::getFlowEdges(FlowEdges &edges) { edges.release(getValueMutable()); }

// The reference is given up here, and the result is a value no flow
// explains: what the operand alone reached is forgotten.
void CountShareOp::getFlowEdges(FlowEdges &edges) { edges.release(getValueMutable()); }

// A new cell: no other value holds a reference to it.
void CellNewOp::getFlowEdges(FlowEdges &edges) { edges.fresh(getCell()); }

// The token's cell is given up here, and the cell made of it, or a new one
// for a null token, is new.
void CellRecycleOp::getFlowEdges(FlowEdges &edges) {
  edges.release(getTokenMutable());
  edges.fresh(getCell());
}

// The value is its cell, so the init takes the cell over and the value is
// new exactly when the cell was; each field given moves into its field of
// the value; and each hole's place is the field the hole is, so what a later
// write through its destination puts there is what that field holds.
void CellInitOp::getFlowEdges(FlowEdges &edges) {
  Value value = getResult();
  DataType data = getDataType();
  Tag tag = getTag();
  edges.flow(FlowSource::of(getCellMutable()), FlowPlace::of(value));
  builtEdges(value, data, tag, getFieldsMutable(), getHoles(), edges);
  for (auto [hole, dest] : llvm::zip_equal(getHoles(), getDests()))
    edges.unify(FlowPlace::partOf(dest, FlowAnchor::holeOf(cast<DestType>(dest.getType()))),
                FlowPlace::partOf(value, FlowAnchor::fieldOf(data, tag, static_cast<unsigned>(hole))));
}

// The value is taken over: its cell becomes the token, and each field
// moves out of it.
void CountTakeOp::getFlowEdges(FlowEdges &edges) {
  OpOperand &value = getValueMutable();
  DataType data = getDataType();
  Tag tag = getTag();
  edges.flow(FlowSource::of(value), FlowPlace::of(getToken()));
  for (auto [index, field] : llvm::enumerate(getFields()))
    edges.flow(FlowSource::partOf(value, FlowAnchor::fieldOf(data, tag, static_cast<unsigned>(index))),
               FlowPlace::of(Value(field)));
}

// The value, which has no cell of its own, is taken over: each field moves
// out of it. A constructor none of whose fields holds a reference moves no
// reference on, so its value is given up whole, else the unpack would read
// as a read of it that leaves it alive.
void CountUnpackOp::getFlowEdges(FlowEdges &edges) {
  OpOperand &value = getValueMutable();
  DataType data = getDataType();
  Tag tag = getTag();
  if (llvm::none_of(getFields(), [](Value field) { return holdsReferences(field.getType()); }))
    edges.release(value);
  for (auto [index, field] : llvm::enumerate(getFields()))
    edges.flow(FlowSource::partOf(value, FlowAnchor::fieldOf(data, tag, static_cast<unsigned>(index))),
               FlowPlace::of(Value(field)));
}

// The token's cell is given up to the value rebuilt in it, which no other
// value holds a reference to; each field moves into its field of it.
void TokenRebuildOp::getFlowEdges(FlowEdges &edges) {
  Value value = getResult();
  DataType data = cast<DataType>(unrestricted(value.getType()));
  edges.release(getTokenMutable());
  builtEdges(value, data, *data.singleTag(), getFieldsMutable(), {}, edges);
  edges.fresh(value);
}

// A buffer upstream made: the reference the result takes is new.
void OwnAdoptOp::getFlowEdges(FlowEdges &edges) { edges.fresh(getResult()); }

// The reference goes to the store that writes the result, which no edge
// follows; the result is the value, read.
void OwnGiveOp::getFlowEdges(FlowEdges &edges) {
  edges.release(getValueMutable());
  edges.flow(FlowSource::of(getValue()), FlowPlace::of(getResult()));
}
