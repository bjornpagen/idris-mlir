// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The ops on arrays a world orders (new, get, set), with their rules, their
// shapes and their effects; the extent of an array to be made; and the tie
// of an array's dimensions to sizes, with what value bounds and the folding
// of a dimension read from it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Canon.h"
#include "idr/IR/Ranges.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ValueBoundsOpInterface.h"

using namespace mlir;
using namespace idr;

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
// grade: plain before idr-rc, and owned after it when it holds references.
LogicalResult verifyElement(Operation *op, StringRef what, Type type, MemRefType array) {
  if (view(type) != array.getElementType())
    return op->emitOpError() << what << " has type " << type << ", but the array holds "
                             << array.getElementType();
  return success();
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

LogicalResult ArrayNewOp::verify() {
  if (failed(verifyCount(*this, getSizes().size(), "sizes", getArrayType())))
    return failure();
  return verifyElement(*this, "the fill", getFill().getType(), getArrayType());
}

// A read that moves its element out leaves the element's place empty, so
// the next IO on its world, its world's one use, is the write that fills
// that place again, in its block: anything else between would see the
// empty place. A machine word is never counted and does not move. Whether
// an element of any other type holds a reference may change as passes run
// (defunctionalization makes a closure a sum, of captured words only, say),
// so it is MoveOutBeforeSet's to ask, and a read that moves an element
// holding none only empties nothing.
LogicalResult ArrayGetOp::verify() {
  if (failed(verifyCount(*this, getIndices().size(), "indices", getArrayType())))
    return failure();
  if (getMoves()) {
    if (getArrayType().getElementType().isIntOrIndexOrFloat())
      return emitOpError("moves out a machine word, which holds no reference");
    auto set = getNext().hasOneUse() ? dyn_cast<ArraySetOp>(*getNext().getUsers().begin())
                                     : ArraySetOp();
    if (!set || set->getBlock() != (*this)->getBlock() ||
        !sameElement(getArray(), getIndices(), set.getArray(), set.getIndices()))
      return emitOpError("moves its element out, but its world does not go next to a write of "
                         "that element in its block");
  }
  return verifyElement(*this, "the result", getValue().getType(), getArrayType());
}

LogicalResult ArraySetOp::verify() {
  if (failed(verifyCount(*this, getIndices().size(), "indices", getArrayType())))
    return failure();
  return verifyElement(*this, "the value", getValue().getType(), getArrayType());
}

// The read before a write of the same element moves the element out.
void ArraySetOp::getCanonicalizationPatterns(RewritePatternSet &results, MLIRContext *context) {
  canon::addMoveOutPatterns(results, context);
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

// Each op's effects are on the array it touches, in the default resource:
// a new array is allocated and written with its fill, a read reads it (and
// writes it when it empties the element's place), and a write reads the
// old element, to release it, and writes the new one. The world orders
// them with every other effect; an access crashes on no index, the index
// being its guard's to check.
void ArrayNewOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  auto array = cast<OpResult>(getArray());
  effects.emplace_back(MemoryEffects::Allocate::get(), array, SideEffects::DefaultResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), array, SideEffects::DefaultResource::get());
}
void ArrayGetOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  OpOperand *array = &getArrayMutable();
  effects.emplace_back(MemoryEffects::Read::get(), array, SideEffects::DefaultResource::get());
  if (getMoves())
    effects.emplace_back(MemoryEffects::Write::get(), array, SideEffects::DefaultResource::get());
}
void ArraySetOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  OpOperand *array = &getArrayMutable();
  effects.emplace_back(MemoryEffects::Read::get(), array, SideEffects::DefaultResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), array, SideEffects::DefaultResource::get());
}

// Any natural may be past the small range, so the conversion may always
// fail: as the allocation of that many elements would.
std::optional<StringRef> NatToExtentOp::getCrashCause() { return StringRef("array too large"); }

// A constant natural that is small is its extent. One that is not stays,
// to fail where it runs.
OpFoldResult NatToExtentOp::fold(FoldAdaptor adaptor) {
  auto big = dyn_cast_or_null<BigAttr>(adaptor.getNatural());
  int64_t value = 0;
  if (!big || big.getValue().getAsInteger(10, value) || value < 0 ||
      value > idr::ranges::smallMax)
    return {};
  return IntegerAttr::get(IndexType::get(getContext()), value);
}

// The natural's range, within what the op lets through: 0 to the largest
// small.
void NatToExtentOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                      SetIntRangeFn setResultRange) {
  idr::ranges::Bounds bounds = idr::ranges::boundsOf(ranges[0]);
  int64_t lo = std::max<int64_t>(bounds.lo.value_or(0), 0);
  int64_t hi = std::min<int64_t>(bounds.hi.value_or(idr::ranges::smallMax), idr::ranges::smallMax);
  if (hi < lo)
    hi = lo;
  setResultRange(getResult(), ConstantIntRanges::fromSigned(
                                  APInt(64, static_cast<uint64_t>(lo), /*isSigned=*/true),
                                  APInt(64, static_cast<uint64_t>(hi), /*isSigned=*/true)));
}

// One size per dynamic dimension. A world-ordered array's length is its
// own, so it is never tied.
LogicalResult TieShapeOp::verify() {
  auto type = cast<ShapedType>(getType());
  if (getDims().size() != static_cast<size_t>(type.getNumDynamicDims()))
    return emitOpError("takes ") << getDims().size() << " sizes for " << type
                                 << ", which has " << type.getNumDynamicDims()
                                 << " dynamic dimensions";
  if (auto memref = dyn_cast<MemRefType>(type);
      memref && isa_and_present<WorldSpaceAttr>(memref.getMemorySpace()))
    return emitOpError("ties ") << type << ", an array a world orders, whose length is its own";
  return success();
}

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
