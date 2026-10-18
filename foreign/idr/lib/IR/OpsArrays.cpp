// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops on arrays a world orders (new, get, set, update), and the update
// of an element of a value array's buffer, with their rules, their shapes,
// their effects and how an element moves; the extent of an array to be
// made; and the tie of an array's dimensions to sizes, with what value
// bounds and the folding of a dimension read from it.

#include "idr/IR/Arrays.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Ranges.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;
using namespace idr::arrays;

namespace {

// An access takes one index per dimension of its array, and a new array one
// size: what memref.load and memref.alloc ask of theirs.
LogicalResult verifyCount(Operation *op, size_t count, StringRef what, MemRefType array) {
  if (count != static_cast<size_t>(array.getRank()))
    return op->emitOpError("takes ") << count << " " << what << " for an array of rank "
                                     << array.getRank();
  return success();
}

// An element moves into an array, or out of it, at the element type at any
// permission: plain before idr-rc, and owned after it when it holds
// references.
LogicalResult verifyElement(Operation *op, StringRef what, Type type, MemRefType array) {
  if (type != atPermission(array.getElementType(), gradeOf(type).permission))
    return op->emitOpError() << what << " has type " << type << ", but the array holds "
                             << array.getElementType();
  return success();
}

// What every update is, on an array a world orders or on a value array's
// buffer alike (UpdateOpInterface), said once. One index per dimension of
// the array, and a region that binds the element alone, at the array's
// element type at any permission, and yields the element, at any
// permission, then each result.
LogicalResult verifyUpdate(UpdateOpInterface op) {
  Operation *self = op.getOperation();
  if (failed(verifyCount(self, op.getIndices().size(), "indices", op.getArrayType())))
    return failure();
  Block &body = self->getRegion(0).front();
  if (body.getNumArguments() != 1)
    return self->emitOpError("binds ")
           << body.getNumArguments() << " values in its region, where it binds the element alone";
  return verifyElement(self, "the element", body.getArgument(0).getType(), op.getArrayType());
}
LogicalResult verifyUpdateEnd(UpdateOpInterface op) {
  SmallVector<Type> types{op.getArrayType().getElementType()};
  llvm::append_range(types, op.getOuts().getTypes());
  return verifyEnd(op.getOperation(), types, [](unsigned at) { return at == 0; });
}

// The region runs once, between the read and the write, and what it gives
// after the element leaves the op.
void updateSuccessors(UpdateOpInterface op, RegionBranchPoint point,
                      SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent())
    regions.push_back(RegionSuccessor(&op->getRegion(0)));
  else
    regions.push_back(RegionSuccessor(op.getOperation()));
}
ValueRange updateSuccessorInputs(UpdateOpInterface op, RegionSuccessor successor) {
  if (successor.isOperation())
    return op.getOuts();
  return ValueRange();
}

// It reads the element out of the array and writes the rebuilt one in, in
// the default resource; the region's effects are its own.
void updateEffects(OpOperand &array,
                   SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  effects.emplace_back(MemoryEffects::Read::get(), &array, SideEffects::DefaultResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), &array, SideEffects::DefaultResource::get());
}

// The element moves out of its place into the region, whose yield moves the
// rebuilt one back in.
void updateEdges(UpdateOpInterface op, FlowEdges &edges) {
  edges.flow(elementsOf(op.getArray()), FlowPoint::of(op.getElement()));
}

// An index as its access's guard was given it: the guard's result is the
// value it checked.
Value unguarded(Value index) {
  if (auto guard = index.getDefiningOp<CheckInBoundsOp>())
    return guard.getIndex();
  return index;
}

// Whether two indices are one: the same value once seen through their
// guards, or two constants of the same value, which a pass that puts a
// constant in place of a value it knows makes once per use.
bool sameIndex(Value x, Value y) {
  x = unguarded(x);
  y = unguarded(y);
  if (x == y)
    return true;
  APInt a, b;
  return matchPattern(x, m_ConstantInt(&a)) && matchPattern(y, m_ConstantInt(&b)) &&
         a.getBitWidth() == b.getBitWidth() && a == b;
}

} // namespace

bool idr::sameElement(Value array, ValueRange indices, Value otherArray, ValueRange otherIndices) {
  return arrayRoot(array) == arrayRoot(otherArray) &&
         llvm::equal(indices, otherIndices, sameIndex);
}

//===----------------------------------------------------------------------===//
// Arrays a world orders
//===----------------------------------------------------------------------===//

LogicalResult ArrayNewOp::verify() {
  if (failed(verifyCount(*this, getSizes().size(), "sizes", getArrayType())))
    return failure();
  return verifyElement(*this, "the fill", getFill().getType(), getArrayType());
}

LogicalResult ArrayGetOp::verify() {
  if (failed(verifyCount(*this, getIndices().size(), "indices", getArrayType())))
    return failure();
  return verifyElement(*this, "the result", getValue().getType(), getArrayType());
}

LogicalResult ArraySetOp::verify() {
  if (failed(verifyCount(*this, getIndices().size(), "indices", getArrayType())))
    return failure();
  return verifyElement(*this, "the value", getValue().getType(), getArrayType());
}

// The read before a write of the same element, with nothing between that
// may read the array, is that element's update.
void ArraySetOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addMoveOutPatterns(results, context);
}

LogicalResult ArrayUpdateOp::verify() { return verifyUpdate(*this); }

LogicalResult ArrayUpdateOp::verifyRegions() { return verifyUpdateEnd(*this); }

void ArrayUpdateOp::getSuccessorRegions(RegionBranchPoint point,
                                        SmallVectorImpl<RegionSuccessor> &regions) {
  updateSuccessors(*this, point, regions);
}

ValueRange ArrayUpdateOp::getSuccessorInputs(RegionSuccessor successor) {
  return updateSuccessorInputs(*this, successor);
}

void ArrayUpdateOp::getRegionInvocationBounds(ArrayRef<Attribute>,
                                              SmallVectorImpl<InvocationBounds> &bounds) {
  bounds.emplace_back(1, 1);
}

// Each dimension of the new array is its size clamped at 0, as an index:
// the length idris_rt_array_new gives a negative size. An array of rank 0
// has none. The world result has no shape.
LogicalResult ArrayNewOp::reifyResultShapes(OpBuilder &b,
                                            ReifiedRankedShapedTypeDims &shapes) {
  Location loc = getLoc();
  SmallVector<OpFoldResult> dims;
  for (Value size : getSizes()) {
    Value zero = arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(0));
    Value length = arith::MaxSIOp::create(b, loc, size, zero);
    dims.push_back(arith::IndexCastOp::create(b, loc, b.getIndexType(), length).getResult());
  }
  shapes.push_back(std::move(dims));
  return success();
}

// An update reads the element out of the array and writes the new one in;
// its region's effects are its own (updateEffects). The other ops declare
// theirs in ODS.
void ArrayUpdateOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  updateEffects(getArrayMutable(), effects);
}

// An element moves in through the fill, which every element holds, and
// through a write; out through a read, and out of an update's place into
// its region, whose yield moves it back in.
void ArrayNewOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowPoint::of(getFillMutable()), elementsOf(getArray()));
  edges.fresh(getArray());
}
void ArrayGetOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(elementsOf(getArray()), FlowPoint::of(getValue()));
}
void ArraySetOp::getFlowEdges(FlowEdges &edges) {
  edges.flow(FlowPoint::of(getValueMutable()), elementsOf(getArray()));
}
void ArrayUpdateOp::getFlowEdges(FlowEdges &edges) { updateEdges(*this, edges); }

//===----------------------------------------------------------------------===//
// The buffer of a value array
//===----------------------------------------------------------------------===//

LogicalResult ElementUpdateOp::verify() { return verifyUpdate(*this); }

LogicalResult ElementUpdateOp::verifyRegions() { return verifyUpdateEnd(*this); }

void ElementUpdateOp::getSuccessorRegions(RegionBranchPoint point,
                                          SmallVectorImpl<RegionSuccessor> &regions) {
  updateSuccessors(*this, point, regions);
}

ValueRange ElementUpdateOp::getSuccessorInputs(RegionSuccessor successor) {
  return updateSuccessorInputs(*this, successor);
}

void ElementUpdateOp::getRegionInvocationBounds(ArrayRef<Attribute>,
                                                SmallVectorImpl<InvocationBounds> &bounds) {
  bounds.emplace_back(1, 1);
}

void ElementUpdateOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  updateEffects(getArrayMutable(), effects);
}

void ElementUpdateOp::getFlowEdges(FlowEdges &edges) { updateEdges(*this, edges); }

//===----------------------------------------------------------------------===//
// The extent of an array to be made
//===----------------------------------------------------------------------===//

// Any natural may be past the small range, so the conversion may always
// fail: as the allocation of that many elements would.
StringRef NatToExtentOp::getCrashCause() { return StringRef("array too large"); }

// A constant natural that is small is its extent. One that is not stays,
// to fail where it runs.
OpFoldResult NatToExtentOp::fold(FoldAdaptor adaptor) {
  auto big = dyn_cast_or_null<BigAttr>(adaptor.getNatural());
  if (!big)
    return {};
  const APInt &value = big.getValue();
  if (value.isNegative() || value.getSignificantBits() > 64 ||
      value.getSExtValue() > IDRIS_RT_SMALL_MAX)
    return {};
  return IntegerAttr::get(IndexType::get(getContext()), value.getSExtValue());
}

// The natural's range, within what the op lets through: 0 to the largest
// small.
void NatToExtentOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                      SetIntRangeFn setResultRange) {
  idr::ranges::Bounds bounds = idr::ranges::boundsOf(ranges[0]);
  int64_t lo = std::max<int64_t>(bounds.lo.value_or(0), 0);
  int64_t hi = std::min<int64_t>(bounds.hi.value_or(IDRIS_RT_SMALL_MAX), IDRIS_RT_SMALL_MAX);
  if (hi < lo)
    hi = lo;
  setResultRange(getResult(), ConstantIntRanges::fromSigned(
                                  APInt(64, static_cast<uint64_t>(lo), /*isSigned=*/true),
                                  APInt(64, static_cast<uint64_t>(hi), /*isSigned=*/true)));
}

//===----------------------------------------------------------------------===//
// Dimensions across calls
//===----------------------------------------------------------------------===//

// One size per dynamic dimension.
LogicalResult TieShapeOp::verify() {
  auto type = cast<ShapedType>(getType());
  if (getDims().size() != static_cast<size_t>(type.getNumDynamicDims()))
    return emitOpError("takes ") << getDims().size() << " sizes for " << type
                                 << ", which has " << type.getNumDynamicDims()
                                 << " dynamic dimensions";
  return success();
}

Value TieShapeOp::getViewSource() { return getValue(); }

// No dynamic dimension, nothing to say; the same sizes said twice, once.
OpFoldResult TieShapeOp::fold(FoldAdaptor) {
  if (getDims().empty())
    return getValue();
  if (auto inner = getValue().getDefiningOp<TieShapeOp>(); inner && inner.getDims() == getDims())
    return getValue();
  return {};
}

// Each dimension: a static one's size, a dynamic one's operand.
LogicalResult TieShapeOp::reifyResultShapes(OpBuilder &b, ReifiedRankedShapedTypeDims &shapes) {
  auto type = cast<ShapedType>(getType());
  SmallVector<OpFoldResult> dims;
  unsigned next = 0;
  for (int64_t size : type.getShape())
    dims.push_back(ShapedType::isDynamic(size) ? OpFoldResult(getDims()[next++])
                                               : OpFoldResult(b.getIndexAttr(size)));
  shapes.push_back(std::move(dims));
  return success();
}

// The result's dimension is its size, and is the operand's: so two arrays
// tied to one size have one dimension, wherever each came from.
void TieShapeOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                 ValueBoundsConstraintSet &cstr) {
  auto type = cast<ShapedType>(getType());
  auto at = static_cast<unsigned>(dim);
  if (type.isDynamicDim(at))
    cstr.bound(value)[dim] == OpFoldResult(getDims()[type.getDynamicDimIndex(at)]);
  else
    cstr.bound(value)[dim] == type.getDimSize(at);
  cstr.bound(value)[dim] == cstr.getExpr(getValue(), dim);
}
