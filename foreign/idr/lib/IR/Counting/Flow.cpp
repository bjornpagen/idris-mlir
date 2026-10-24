// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// How the values of counting's ops move, as data (FlowEdges.h), for the
// ownership markings that read the program while these ops stand in it:
// each op that exists from counting's first step to exclusivity states
// where what it holds, takes or gives goes. A value is followed whole, or
// into and out of a field of another. The ops reuse and the expansion
// make, after every marking has read the program, state nothing; the fused
// take ends its owner, as its trait says. And the one rule placement and
// the linearity rule read of what any op does with a counted operand's
// reference, from what the op declares (Counting.h).

#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Flow.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <optional>

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

// The token's emptied cell is freed here: the token gives its reference up.
void TokenFreeOp::getFlowEdges(FlowEdges &edges) { edges.release(getTokenMutable()); }

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

namespace {

// The value is taken over: its cell becomes the token, and each field
// moves out of it into its result, a field's value or the array a field
// holds as its buffer, which is that buffer.
template <TakesOutOfCell Op>
void takenEdges(Op op, FlowEdges &edges) {
  OpOperand &value = op.getValueMutable();
  DataType data = op.getDataType();
  Tag tag = op.getTag();
  edges.flow(FlowSource::of(value), FlowPlace::of(op.getToken()));
  for (auto [index, field] : llvm::enumerate(op.getFields()))
    edges.flow(FlowSource::partOf(value, FlowAnchor::fieldOf(data, tag, static_cast<unsigned>(index))),
               FlowPlace::of(Value(field)));
}

} // namespace

void CountTakeOp::getFlowEdges(FlowEdges &edges) { takenEdges(*this, edges); }

void CountTakeOpenOp::getFlowEdges(FlowEdges &edges) { takenEdges(*this, edges); }

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

//===----------------------------------------------------------------------===//
// What an op does with a counted operand's reference
//===----------------------------------------------------------------------===//

namespace {

// The use an edge moves on or gives up: the source of a flow that is the
// use itself, or a part of a use the op takes over, or the use a release
// gives up. A part read out of a value the op only reads moves none, and
// every other edge moves none.
std::optional<OpOperand *> movedBy(const FlowEdges::Edge &edge) {
  using Moved = std::optional<OpOperand *>;
  return match(
      edge.move,
      [](const FlowEdges::Flow &flow) -> Moved {
        return match(
            flow.from.at, [](const FlowSource::Taken &taken) -> Moved { return taken.use; },
            [](const FlowSource::Part &part) -> Moved { return part.taken(); },
            [](const OneOf<FlowSource::Whole, FlowSource::Parameter, FlowSource::Result> auto &)
                -> Moved { return std::nullopt; });
      },
      [](const FlowEdges::Release &release) -> Moved { return release.use; },
      [](const OneOf<FlowEdges::Unify, FlowEdges::Source, FlowEdges::Fresh, FlowEdges::Overwrite,
                     FlowEdges::Fill, FlowEdges::Constant, FlowEdges::Dispatch> auto &) -> Moved {
        return std::nullopt;
      });
}

} // namespace

llvm::SmallBitVector idr::movesOf(Operation *op) {
  llvm::SmallBitVector moved(op->getNumOperands());
  if (op->getNumOperands() != 0 &&
      (op->hasTrait<EndsOwner>() || op->hasTrait<RunsOnceGivingBack>()))
    moved.set(0);
  FlowEdges edges;
  flowEdgesOf(op, edges);
  for (const FlowEdges::Edge &edge : edges.edges())
    if (std::optional<OpOperand *> use = movedBy(edge)) {
      assert((*use)->getOwner() == op && "an op's edges move only its own uses");
      moved.set((*use)->getOperandNumber());
    }
  return moved;
}

llvm::SmallBitVector idr::movedOn(Operation *op) {
  llvm::SmallBitVector moved = movesOf(op);
  for (OpOperand &use : op->getOpOperands())
    if (!freedBy(use.get().getType(), Release::Counted))
      moved.reset(use.getOperandNumber());
  return moved;
}

Reference idr::referenceAt(OpOperand &use) {
  return movedOn(use.getOwner()).test(use.getOperandNumber()) ? Reference::MovedOn
                                                              : Reference::Kept;
}
