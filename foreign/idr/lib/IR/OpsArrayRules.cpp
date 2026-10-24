// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The rules the ops on arrays share, each said once (idr/IR/Arrays.h): what
// an array holds at an index, where an element moves and where a generating
// op's destinations go; what memory an element's place, empty while it is
// rebuilt, may not see touched; and what a region of the generating set must
// end in and bind, which destinations it places into, and its domain, bounds
// and iterator types.

#include "idr/IR/Arrays.h"
#include "idr/IR/Effects/Classify.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"

using namespace mlir;
using namespace idr;

namespace idr::arrays {

// What each rule says is in idr/IR/Arrays.h.

Type cellOf(ShapedType array, unsigned lead) {
  if (lead == array.getRank())
    return array.getElementType();
  ArrayRef<int64_t> shape = array.getShape().drop_front(lead);
  if (isa<RankedTensorType>(array))
    return RankedTensorType::get(shape, array.getElementType());
  return MemRefType::get(shape, array.getElementType());
}

bool sameLead(ShapedType a, ShapedType b, unsigned lead) {
  return a.getRank() >= lead && b.getRank() >= lead &&
         a.getShape().take_front(lead) == b.getShape().take_front(lead);
}

FlowAnchor elementsOf(Value array) {
  auto shaped = cast<ShapedType>(unrestricted(array.getType()));
  return FlowAnchor::elementsOf(shaped.getElementType());
}

FlowSource atIndex(OpOperand &use) {
  if (auto cell = dyn_cast<ShapedType>(use.get().getType()))
    return FlowSource::partOf(use, FlowAnchor::elementsOf(cell.getElementType()));
  return FlowSource::of(use);
}
FlowPlace atIndex(Value value) {
  if (isa<ShapedType>(value.getType()))
    return FlowPlace::partOf(value, elementsOf(value));
  return FlowPlace::of(value);
}

void destinationEdges(DestinationStyleOpInterface op, FlowEdges &edges) {
  for (OpResult result : op->getResults())
    edges.flow(FlowSource::of(*op.getTiedOpOperand(result)), FlowPlace::of(result));
}

bool onContents(const effects::Effect &each) {
  return each.kind != effects::Kind::Allocate &&
         effects::atOrAbove[effects::ResourceId::Contents].contains(each.resource);
}

namespace {

// What the place an update empties may see: a read or a write of the
// contents or of a state above them. A free or an allocation on the heap
// gives memory back or takes it, never what a place holds, and a cell
// being filled, beneath the contents, is reached by no value but its own,
// so counting's own work in the region passes. Which value an effect names
// is not read: a call writing through a cell that holds the array reaches
// the place.
bool seesEmptyPlace(const effects::Effect &each) {
  constexpr effects::Kinds readsOrWrites{effects::Kind::Read, effects::Kind::Write};
  return readsOrWrites.contains(each.kind) &&
         effects::atOrAbove[effects::ResourceId::Contents].contains(each.resource);
}

} // namespace

bool touchesInPlace(Operation *op) {
  return effects::classify(op, seesEmptyPlace) == effects::Does::Touches;
}

void generatingSuccessors(Operation *op, SmallVectorImpl<RegionSuccessor> &regions) {
  regions.push_back(RegionSuccessor(&op->getRegion(0)));
  regions.push_back(RegionSuccessor(op));
}

LogicalResult verifyEnd(Operation *op, TypeRange types) {
  auto yield = dyn_cast<ArrayYieldOp>(op->getRegion(0).front().getTerminator());
  if (!yield)
    return success();
  if (yield.getValues().getTypes() != types)
    return yield.emitOpError("yields ") << yield.getValues().getTypes() << " where "
                                        << op->getName() << " takes " << types;
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

memref::AllocOp allocationOf(Value buffer) {
  if (auto adopted = buffer.getDefiningOp<OwnAdoptOp>())
    buffer = adopted.getValue();
  return buffer.getDefiningOp<memref::AllocOp>();
}

LogicalResult verifyFresh(DestinationStyleOpInterface op) {
  for (Value out : op.getDpsInits()) {
    auto type = cast<ShapedType>(out.getType());
    if (!holdsReferences(type.getElementType()))
      continue;
    auto alloc = out.getDefiningOp<bufferization::AllocTensorOp>();
    bool fresh = isa<RankedTensorType>(type)
                     ? out.getDefiningOp<tensor::EmptyOp>() || (alloc && !alloc.getCopy())
                     : static_cast<bool>(allocationOf(out));
    if (!fresh)
      return op->emitOpError("places elements that hold references into ")
             << type << ", which is no fresh array";
  }
  return success();
}

OpFoldResult sizeOf(OpBuilder &b, Location loc, Value array, unsigned dim) {
  // A tensor's dimension and a buffer's are two ops, one per dialect.
  if (isa<RankedTensorType>(array.getType()))
    return tensor::getMixedSize(b, loc, array, dim);
  return memref::getMixedSize(b, loc, array, dim);
}

// The last axis of a fold or a scan is its length, which a scan's
// destination also has and a fold's has not; every other dimension of the
// domain is the first destination's.
DomainSize extentOf(DestinationStyleOpInterface op, unsigned dim) {
  if (auto fold = dyn_cast<LastAxisFoldOpInterface>(op.getOperation());
      fold && dim == fold.getFrameRank())
    return {fold.getLength(), std::nullopt};
  return {op.getDpsInits().front(), static_cast<int64_t>(dim)};
}

void boundIndex(DestinationStyleOpInterface op, Value value, Block::BlockArgListType indices,
                ValueBoundsConstraintSet &cstr) {
  auto index = dyn_cast<BlockArgument>(value);
  if (!index || indices.empty() || index.getOwner() != indices.front().getOwner() ||
      index.getArgNumber() >= indices.size())
    return;
  cstr.bound(value) >= 0;
  cstr.bound(value) < extentOf(op, index.getArgNumber()).term(cstr);
}

SmallVector<Range> domainOf(OpBuilder &b, DestinationStyleOpInterface op, unsigned rank) {
  Location loc = op.getLoc();
  OpFoldResult zero = b.getIndexAttr(0);
  OpFoldResult one = b.getIndexAttr(1);
  auto fold = dyn_cast<LastAxisFoldOpInterface>(op.getOperation());
  return llvm::map_to_vector(llvm::seq(0u, rank), [&](unsigned dim) {
    OpFoldResult size = fold && dim == fold.getFrameRank()
                            ? OpFoldResult(fold.getLength())
                            : sizeOf(b, loc, op.getDpsInits().front(), dim);
    return Range{zero, size, one};
  });
}

bool computes(Operation *op) {
  Block &body = op->getRegion(0).front();
  return isa<ArrayYieldOp>(body.getTerminator()) &&
         llvm::all_of(body.without_terminator(),
                      [](Operation &inner) { return effects::whole(&inner).onlyComputes(); });
}

SmallVector<utils::IteratorType> iteratorsOf(Operation *op, unsigned rank, unsigned frame) {
  utils::IteratorType across =
      computes(op) ? utils::IteratorType::parallel : utils::IteratorType::reduction;
  SmallVector<utils::IteratorType> iterators(frame, across);
  iterators.append(rank - frame, utils::IteratorType::reduction);
  return iterators;
}

} // namespace idr::arrays
