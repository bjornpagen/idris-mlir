// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The sizes of arrays: a natural as the extent of an array to be made,
// idr.nat.to_extent, with its fold and its range; and the tie of an array's
// dimensions to sizes across calls, idr.array.tie_shape, with its fold,
// what value bounds reads of the dimensions it ties, that it gives its
// array on with no run-time work, and its type, its operand's.

#include "idr/IR/Arrays.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Ranges.h"

#include "mlir/IR/BuiltinTypeInterfaces.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"

#include <algorithm>
#include <cstddef>
#include <optional>

// The runtime's C ABI: the largest small natural.
#include "idris_rt.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The extent of an array to be made
//===----------------------------------------------------------------------===//

// A constant natural that is small is its extent. One that is not stays,
// to end the run as out of memory where it runs: no allocation of that
// many elements can be made.
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

// The same array at its operand's type, given one size per dynamic
// dimension of it. Operands the sizes do not number have no result: where
// a re-inference made the array more static (a copy's input made static)
// the tie refuses it, and keeps its type reading its operand cast back,
// the less optimized form and never a wrong one. The interface's verifier
// runs this at the op, so it holds the result to the operand's type and
// the sizes to its dimensions. The operand's constraint makes it a ranked
// tensor or a value array's buffer, at a grade only on the buffer, so its
// carrier is shaped.
LogicalResult ArrayTieShapeOp::inferReturnTypes(MLIRContext *, std::optional<Location> location,
                                                Adaptor adaptor, SmallVectorImpl<Type> &inferred) {
  Type array = adaptor.getValue().getType();
  auto shape = cast<ShapedType>(unrestricted(array));
  if (adaptor.getDims().size() != static_cast<size_t>(shape.getNumDynamicDims()))
    return emitOptionalError(location, "takes ", adaptor.getDims().size(), " sizes for ", array,
                             ", which has ", shape.getNumDynamicDims(), " dynamic dimensions");
  inferred.push_back(array);
  return success();
}

Value ArrayTieShapeOp::getViewSource() { return getValue(); }

// The same array, its words untouched: the sizes it ties are a fact for
// the compiler, so a call whose result it takes is still the tail.
Carry ArrayTieShapeOp::getCarry() { return Carry::Free; }

// Its type is its operand's, as its inference says, whatever that is.
Type ArrayTieShapeOp::getCarriedType(Type operand) { return operand; }

// No dynamic dimension, nothing to say; the same sizes said twice, once.
OpFoldResult ArrayTieShapeOp::fold(FoldAdaptor) {
  if (getDims().empty())
    return getValue();
  if (auto inner = getValue().getDefiningOp<ArrayTieShapeOp>();
      inner && inner.getDims() == getDims())
    return getValue();
  return {};
}

// Each dimension: a static one's size, a dynamic one's operand. Upstream
// reifies the shapes of shaped results alone, one entry each, and checks
// that count when it asks: a graded buffer is no shaped value to it, so a
// tie of one has no entry, where one read from its carrier would be an
// entry too many.
LogicalResult ArrayTieShapeOp::reifyResultShapes(OpBuilder &b,
                                                 ReifiedRankedShapedTypeDims &shapes) {
  auto type = dyn_cast<ShapedType>(getType());
  if (!type)
    return success();
  SmallVector<OpFoldResult> dims;
  unsigned next = 0;
  for (int64_t size : type.getShape())
    dims.push_back(ShapedType::isDynamic(size) ? OpFoldResult(getDims()[next++])
                                               : OpFoldResult(b.getIndexAttr(size)));
  shapes.push_back(std::move(dims));
  return success();
}

// The result's dimension is its size, and is the operand's: so two arrays
// tied to one size have one dimension, wherever each came from. Value
// bounds asks a dimension only of a shaped value, here the tie's one
// result, so its type is shaped: a graded tie is never asked, and its
// operand, of the same type, is shaped with it.
void ArrayTieShapeOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                 ValueBoundsConstraintSet &cstr) {
  auto type = cast<ShapedType>(value.getType());
  auto at = static_cast<unsigned>(dim);
  if (type.isDynamicDim(at))
    cstr.bound(value)[dim] == OpFoldResult(getDims()[type.getDynamicDimIndex(at)]);
  else
    cstr.bound(value)[dim] == type.getDimSize(at);
  cstr.bound(value)[dim] == cstr.getExpr(getValue(), dim);
}
