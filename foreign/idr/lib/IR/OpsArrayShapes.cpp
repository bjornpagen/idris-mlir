// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The sizes of arrays: a natural as the extent of an array to be made,
// idr.nat.to_extent, with its fold and its range; and the tie of the axes
// of an array something states to sizes across calls, idr.array.tie_shape,
// with its fold, what value bounds reads of the dimensions it ties, that it
// gives its array on with no run-time work, and its type, its operand's.

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

namespace {

// Where among a tie's sizes axis `dim`'s is, where the tie names the axis:
// its axes increase, so one search finds it. None for an axis it does not
// name: nothing stated that axis, and the tie leaves it as it is.
std::optional<unsigned> tiedAt(ArrayTieShapeOp tie, int64_t dim) {
  ArrayRef<int32_t> axes = tie.getAxes();
  const int32_t *at = llvm::lower_bound(axes, dim);
  if (at == axes.end() || *at != dim)
    return std::nullopt;
  return static_cast<unsigned>(at - axes.begin());
}

} // namespace

// The same array at its operand's type, given one size per axis it names,
// each a dynamic dimension of it. Operands where an axis it names is no
// dynamic dimension have no result: where a re-inference made a tied axis
// static (a copy's input made static) the tie refuses it, and keeps its
// type reading its operand cast back, the less optimized form and never a
// wrong one. The interface's verifier runs this at the op, so it holds the
// result to the operand's type and the sizes to its axes. The operand's
// constraint makes it a ranked tensor or a value array's buffer, at a
// grade only on the buffer, so its carrier is shaped; the axes' own
// constraint makes them increasing and none negative.
LogicalResult ArrayTieShapeOp::inferReturnTypes(MLIRContext *, std::optional<Location> location,
                                                Adaptor adaptor, SmallVectorImpl<Type> &inferred) {
  Type array = adaptor.getValue().getType();
  auto shape = cast<ShapedType>(unrestricted(array));
  ArrayRef<int32_t> axes = adaptor.getAxes();
  if (adaptor.getDims().size() != axes.size())
    return emitOptionalError(location, "takes ", adaptor.getDims().size(), " sizes for ",
                             axes.size(), " axes");
  for (int32_t axis : axes)
    if (axis >= shape.getRank() || !shape.isDynamicDim(static_cast<unsigned>(axis)))
      return emitOptionalError(location, "ties axis ", axis, " of ", array,
                               ", which is no dynamic dimension of it");
  inferred.push_back(array);
  return success();
}

Value ArrayTieShapeOp::getViewSource() { return getValue(); }

// The same array, its words untouched: the sizes it ties are a fact for
// the compiler, so a call whose result it takes is still the tail.
Carry ArrayTieShapeOp::getCarry() { return Carry::Free; }

// Its type is its operand's, as its inference says, whatever that is.
Type ArrayTieShapeOp::getCarriedType(Type operand) { return operand; }

// Its meaning's attribute instance (Ops/Folds.h).
OpFoldResult ArrayTieShapeOp::fold(FoldAdaptor adaptor) {
  fold::InParts where(getContext());
  return fold::foldResultOf(meaning(where, *this, adaptor.getOperands()));
}

// Each dimension: a tied one's size, and any other the operand's own,
// static or read off it, which the result is. Upstream reifies the shapes
// of shaped results alone, one entry each, and checks that count when it
// asks: a graded buffer is no shaped value to it, so a tie of one has no
// entry, where one read from its carrier would be an entry too many.
LogicalResult ArrayTieShapeOp::reifyResultShapes(OpBuilder &b,
                                                 ReifiedRankedShapedTypeDims &shapes) {
  auto type = dyn_cast<ShapedType>(getType());
  if (!type)
    return success();
  SmallVector<OpFoldResult> dims;
  for (int64_t dim = 0, rank = type.getRank(); dim < rank; ++dim) {
    std::optional<unsigned> at = tiedAt(*this, dim);
    dims.push_back(at ? OpFoldResult(getDims()[*at])
                      : idr::arrays::sizeOf(b, getLoc(), getValue(), static_cast<unsigned>(dim)));
  }
  shapes.push_back(std::move(dims));
  return success();
}

// The result's dimension is the operand's, and its size where the tie
// names it: so two arrays tied to one size have one dimension, wherever
// each came from. Value bounds asks a dimension only of a shaped value,
// here the tie's one result, so its type is shaped: a graded tie is never
// asked, and its operand, of the same type, is shaped with it.
void ArrayTieShapeOp::populateBoundsForShapedValueDim(Value value, int64_t dim,
                                                      ValueBoundsConstraintSet &cstr) {
  auto type = cast<ShapedType>(value.getType());
  auto axis = static_cast<unsigned>(dim);
  if (!type.isDynamicDim(axis))
    cstr.bound(value)[dim] == type.getDimSize(axis);
  else if (std::optional<unsigned> at = tiedAt(*this, dim))
    cstr.bound(value)[dim] == OpFoldResult(getDims()[*at]);
  cstr.bound(value)[dim] == cstr.getExpr(getValue(), dim);
}
