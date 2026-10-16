// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The guards: each decides its own condition, folds to its operand where
// the operand shows that the condition holds, and narrows the operand's
// range by it. And what the pure total ops ask of them: when such an op may
// run before the guard its ODS names.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"

#include "mlir/IR/Matchers.h"

#include "idris_rt.h"

#include <algorithm>
#include <limits>

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The conditions
//===----------------------------------------------------------------------===//

namespace {

// The integer constant at `at`, or null.
IntegerAttr word(ArrayRef<Attribute> constants, size_t at) {
  return dyn_cast_or_null<IntegerAttr>(constants[at]);
}

} // namespace

bool CheckNonzeroOp::holds(ArrayRef<Attribute> constants) {
  if (constants.size() != 1)
    return false;
  if (auto big = dyn_cast_or_null<BigAttr>(constants[0]))
    return !big.getValue().isZero();
  return word(constants, 0) && !word(constants, 0).getValue().isZero();
}

// The length is the runtime's count of the string's characters, which is
// what idr.str.length folds to.
bool CheckInBoundsOp::holds(ArrayRef<Attribute> constants) {
  if (constants.size() != 2)
    return false;
  IntegerAttr index = word(constants, 0);
  auto text = dyn_cast_or_null<StringAttr>(constants[1]);
  if (!index || !text || index.getValue().isNegative())
    return false;
  fold::Scope scope(text.getContext());
  int64_t length = fold::runtime<StrLengthOp>(scope.str(text));
  return index.getValue().slt(length);
}

bool CheckNonemptyOp::holds(ArrayRef<Attribute> constants) {
  if (constants.size() != 1)
    return false;
  auto str = dyn_cast_or_null<StringAttr>(constants[0]);
  return str && !str.getValue().empty();
}

bool CheckFiniteOp::holds(ArrayRef<Attribute> constants) {
  if (constants.size() != 1)
    return false;
  auto value = dyn_cast_or_null<FloatAttr>(constants[0]);
  return value && value.getValue().isFinite();
}

bool CheckRangeOp::holds(ArrayRef<Attribute> constants) {
  if (constants.size() != 3 || !word(constants, 0) || !word(constants, 1) || !word(constants, 2))
    return false;
  APInt offset = word(constants, 0).getValue(), count = word(constants, 1).getValue();
  bool overflow = false;
  APInt end = offset.sadd_ov(count, overflow);
  return !offset.isNegative() && !count.isNegative() && !overflow &&
         end.sle(word(constants, 2).getValue());
}

//===----------------------------------------------------------------------===//
// Folding
//===----------------------------------------------------------------------===//

namespace {

// Whether the value `op` checks is the result of a guard identical to it,
// the same guard with its other operands, which has checked it already.
bool checkedBefore(Operation *op) {
  Operation *before = op->getOperand(0).getDefiningOp();
  return before && before->getName() == op->getName() &&
         llvm::equal(before->getOperands().drop_front(), op->getOperands().drop_front());
}

// The value `op` checks, where its condition holds of the constants that
// folding or constant propagation knows its operands to be (`holds`),
// where `known` says it holds of the operand, or where an identical guard
// checked it. Nothing otherwise: a guard that would crash keeps its crash.
OpFoldResult foldCheck(Operation *op, bool holds, bool known) {
  if (holds || known || checkedBefore(op))
    return op->getOperand(0);
  return {};
}

} // namespace

OpFoldResult CheckNonzeroOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, holds(adaptor.getOperands()), knownNonZero(getValue()));
}

OpFoldResult CheckInBoundsOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, holds(adaptor.getOperands()), false);
}

// A string built with a character or a number in it is not empty, which
// lets a head read the character off the string it was built from.
OpFoldResult CheckNonemptyOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, holds(adaptor.getOperands()), knownNonEmpty(getStr()));
}

OpFoldResult CheckFiniteOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, holds(adaptor.getOperands()), knownFinite(getValue()));
}

OpFoldResult CheckRangeOp::fold(FoldAdaptor adaptor) {
  return foldCheck(*this, holds(adaptor.getOperands()), false);
}

//===----------------------------------------------------------------------===//
// Ranges
//===----------------------------------------------------------------------===//

namespace {

// `range`, an i64's, narrowed to the signed interval [lo, hi] the guard's
// condition leaves. Where it leaves nothing the guard always crashes and
// nothing reads its result, so the range stays as it was.
ConstantIntRanges within(const ConstantIntRanges &range, int64_t lo, int64_t hi) {
  if (range.smin().getBitWidth() != 64 || lo > hi)
    return range;
  ConstantIntRanges narrowed = range.intersection(ConstantIntRanges::fromSigned(
      APInt(64, static_cast<uint64_t>(lo), /*isSigned=*/true),
      APInt(64, static_cast<uint64_t>(hi), /*isSigned=*/true)));
  if (narrowed.smin().sgt(narrowed.smax()) || narrowed.umin().ugt(narrowed.umax()))
    return range;
  return narrowed;
}

} // namespace

// Not zero: an end of the range at zero moves past it. A big's range is
// its value's, as idr.ranges states it, so the same holds of it.
void CheckNonzeroOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                       SetIntRangeFn setResultRange) {
  const ConstantIntRanges &range = ranges[0];
  unsigned width = range.umin().getBitWidth();
  // No integer the analysis sees, or zero alone, which always crashes.
  if (width < 2 || range.umax().isZero() || (range.smin().isZero() && range.smax().isZero())) {
    setResultRange(getChecked(), range);
    return;
  }
  APInt one(width, 1);
  setResultRange(getChecked(),
                 ConstantIntRanges(range.umin().isZero() ? one : range.umin(), range.umax(),
                                   range.smin().isZero() ? one : range.smin(),
                                   range.smax().isZero() ? APInt::getAllOnes(width)
                                                         : range.smax()));
}

// At least 0, and below the length of what it indexes, which no range
// states: a length is at most the largest i64.
void CheckInBoundsOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                                    SetIntLatticeFn setResultRange) {
  if (ranges[0].isUninitialized())
    return;
  setResultRange(getChecked(), IntegerValueRange(within(ranges[0].getValue(), 0,
                                                        std::numeric_limits<int64_t>::max() - 1)));
}

// At least 0, and at most the size's greatest value less the least count,
// which is not negative either.
void CheckRangeOp::inferResultRanges(ArrayRef<ConstantIntRanges> ranges,
                                     SetIntRangeFn setResultRange) {
  const APInt &count = ranges[1].smin(), &size = ranges[2].smax();
  if (count.getBitWidth() != 64 || size.getBitWidth() != 64 || size.isNegative()) {
    setResultRange(getChecked(), ranges[0]);
    return;
  }
  int64_t least = std::max<int64_t>(count.getSExtValue(), 0);
  setResultRange(getChecked(), within(ranges[0], 0, size.getSExtValue() - least));
}

//===----------------------------------------------------------------------===//
// Speculation
//===----------------------------------------------------------------------===//

// Past the guard: the value is the result of the guard, which checked it
// against these operands. Or no guard is needed: the constants the value
// and these operands are pass its condition. One rule for every guard; a
// string index's string is the operand it is checked against.
Speculation::Speculatability
idr::guardedSpeculatability(Value guarded, ValueRange against,
                            function_ref<bool(Operation *)> isGuard,
                            function_ref<bool(ArrayRef<Attribute>)> holds) {
  Operation *guard = guarded.getDefiningOp();
  if (guard && isGuard(guard) && llvm::equal(guard->getOperands().drop_front(), against))
    return Speculation::Speculatable;
  SmallVector<Value, 2> operands{guarded};
  llvm::append_range(operands, against);
  SmallVector<Attribute, 2> constants;
  for (Value operand : operands) {
    Attribute constant;
    matchPattern(operand, m_Constant(&constant));
    constants.push_back(constant);
  }
  return holds(constants) ? Speculation::Speculatable : Speculation::NotSpeculatable;
}
