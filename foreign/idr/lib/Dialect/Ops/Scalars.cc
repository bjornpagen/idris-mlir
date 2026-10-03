// The conversions of scalars: to a character, a byte or an integer, and
// the first character of a number's text.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

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

OpFoldResult ToByteOp::fold(FoldAdaptor adaptor) {
  if (!ops::isByte(adaptor.getValue()))
    return {};
  return IntegerAttr::get(getType(), cast<IntegerAttr>(adaptor.getValue()).getValue().trunc(8));
}

std::optional<StringRef> ToByteOp::getCrashCause() {
  Attribute constant;
  if (matchPattern(getValue(), m_Constant(&constant)) && ops::isByte(constant))
    return std::nullopt;
  return StringRef("a byte outside 0 to 255");
}

void ToByteOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), ops::nonNegative(8, 0, 255));
}

OpFoldResult ToIntOp::fold(FoldAdaptor adaptor) {
  auto value = dyn_cast_or_null<FloatAttr>(adaptor.getValue());
  if (!value || !value.getValue().isFinite())
    return {};
  // Truncated exactly, then wrapped: 1100 bits hold any finite double.
  APSInt whole(1100, /*isUnsigned=*/false);
  bool exact = false;
  value.getValue().convertToInteger(whole, APFloat::rmTowardZero, &exact);
  return IntegerAttr::get(getType(), whole.trunc(getType().getIntOrFloatBitWidth()));
}

std::optional<StringRef> ToIntOp::getCrashCause() {
  if (knownFinite(getValue()))
    return std::nullopt;
  return StringRef("cast of a non-finite Double");
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
