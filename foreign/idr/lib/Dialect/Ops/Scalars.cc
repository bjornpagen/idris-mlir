// The conversions of scalars: to a character, a byte or an integer, and
// the first character of a number's text; and when a division or a
// conversion may run before the guard of its operand.

#include "idr/Idr.h"

import idr.ops;

using namespace mlir;
using namespace idr;

OpFoldResult ToCharOp::fold(FoldAdaptor adaptor) {
  auto value = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!value)
    return {};
  const APInt &bits = value.getValue();
  bool negative = getIsSigned() && bits.isNegative();
  uint64_t code = negative || bits.getActiveBits() > 32 ? UINT64_MAX
                                                        : bits.getZExtValue();
  bool scalar = code <= 0xD7FF || (code >= 0xE000 && code <= 0x10FFFF);
  return IntegerAttr::get(getType(), scalar ? static_cast<int64_t>(code) : 0);
}

void ToCharOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), ops::nonNegative(32, 0, 0x10FFFF));
}

// A value its guard refuses folds to nothing: the program never converts
// it, since the guard crashes first.
OpFoldResult ToByteOp::fold(FoldAdaptor adaptor) {
  if (!checkHolds(CheckKind::Byte, adaptor.getValue()))
    return {};
  return IntegerAttr::get(getType(), cast<IntegerAttr>(adaptor.getValue()).getValue().trunc(8));
}

void ToByteOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), ops::nonNegative(8, 0, 255));
}

Speculation::Speculatability ToByteOp::getSpeculatability() {
  return checkSpeculatability(*this, getValueMutable().getOperandNumber());
}

OpFoldResult ToIntOp::fold(FoldAdaptor adaptor) {
  if (!checkHolds(CheckKind::Finite, adaptor.getValue()))
    return {};
  auto value = cast<FloatAttr>(adaptor.getValue());
  // Truncated exactly, then wrapped: 1100 bits hold any finite double.
  APSInt whole(1100, /*isUnsigned=*/false);
  bool exact = false;
  value.getValue().convertToInteger(whole, APFloat::rmTowardZero, &exact);
  return IntegerAttr::get(getType(), whole.trunc(getType().getIntOrFloatBitWidth()));
}

Speculation::Speculatability ToIntOp::getSpeculatability() {
  return checkSpeculatability(*this, getValueMutable().getOperandNumber());
}

// A division by a divisor its guard has not checked could fault, so it
// stays below the guard, or below the path that proved the guard away.
Speculation::Speculatability DivOp::getSpeculatability() {
  return checkSpeculatability(*this, getRhsMutable().getOperandNumber());
}

Speculation::Speculatability ModOp::getSpeculatability() {
  return checkSpeculatability(*this, getRhsMutable().getOperandNumber());
}

// '-', a digit, or the first letter of `inf` or `nan`.
void DoubleHeadOp::inferResultRanges(ArrayRef<ConstantIntRanges>,
                                     SetIntRangeFn setResultRange) {
  setResultRange(getResult(), ops::nonNegative(32, '-', 'n'));
}

// '-' or a digit; a digit when unsigned.
void IntHeadOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), ops::nonNegative(32, getIsSigned() ? '-' : '0', '9'));
}
