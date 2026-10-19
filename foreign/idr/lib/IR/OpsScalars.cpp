// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The conversions of scalars: to a character or an integer, and the first
// character of a number's text; and idr.lin.enter and idr.lin.use, a value
// moved into a linear type and used out of it, whose ranges pass through.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"

#include "llvm/ADT/APSInt.h"

#include <cstdint>

using namespace mlir;
using namespace idr;

namespace {

// An integer, read as the op's signedness says, as a Char: itself if it is
// a scalar value, else 0. A negative signed integer is no scalar value; an
// unsigned one is the natural its bits are.
template <typename ToChar>
OpFoldResult foldToChar(ToChar op, typename ToChar::FoldAdaptor adaptor) {
  auto value = dyn_cast_or_null<IntegerAttr>(adaptor.getValue());
  if (!value)
    return {};
  const APInt &bits = value.getValue();
  bool negative = ToChar::isSigned && bits.isNegative();
  uint64_t code = negative || bits.getActiveBits() > 32 ? UINT64_MAX
                                                        : bits.getZExtValue();
  bool scalar = code <= 0xD7FF || (code >= 0xE000 && code <= 0x10FFFF);
  return IntegerAttr::get(op.getType(), scalar ? static_cast<int64_t>(code) : 0);
}

// A scalar value or 0, however the integer is read.
template <typename ToChar>
void toCharRanges(ToChar op, SetIntRangeFn setResultRange) {
  setResultRange(op.getResult(), idr::ranges::nonNegative(32, 0, 0x10FFFF));
}

// '-' or a digit of a signed integer; a digit of an unsigned one.
template <typename IntHead>
void intHeadRanges(IntHead op, SetIntRangeFn setResultRange) {
  setResultRange(op.getResult(),
                 idr::ranges::nonNegative(32, IntHead::isSigned ? '-' : '0', '9'));
}

} // namespace

OpFoldResult ToCharSOp::fold(FoldAdaptor adaptor) { return foldToChar(*this, adaptor); }
OpFoldResult ToCharUOp::fold(FoldAdaptor adaptor) { return foldToChar(*this, adaptor); }

void ToCharSOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  toCharRanges(*this, setResultRange);
}
void ToCharUOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  toCharRanges(*this, setResultRange);
}

// A value its guard refuses folds to nothing: the program never converts
// it, since the guard crashes first.
OpFoldResult ToIntOp::fold(FoldAdaptor adaptor) {
  if (!guardHolds(adaptor))
    return {};
  auto value = cast<FloatAttr>(adaptor.getValue());
  // Truncated exactly, then wrapped: 1100 bits hold any finite double.
  APSInt whole(1100, /*isUnsigned=*/false);
  bool exact = false;
  value.getValue().convertToInteger(whole, APFloat::rmTowardZero, &exact);
  return IntegerAttr::get(getType(), whole.trunc(getType().getIntOrFloatBitWidth()));
}

// '-', a digit, or the first letter of `inf` or `nan`.
void DoubleHeadOp::inferResultRanges(ArrayRef<ConstantIntRanges>,
                                     SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(32, '-', 'n'));
}

void IntHeadSOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  intHeadRanges(*this, setResultRange);
}
void IntHeadUOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  intHeadRanges(*this, setResultRange);
}

//===----------------------------------------------------------------------===//
// The linear positions
//===----------------------------------------------------------------------===//

// The value an entry used at once held, and the linear value a use entered
// at once was. A value that holds a linear one is linear by its type (a
// closure's quantity is its type), so no entry takes one: the value an
// entry takes may be read many times.
OpFoldResult LinUseOp::fold(FoldAdaptor) {
  if (auto enter = getLinear().getDefiningOp<LinEnterOp>())
    return enter.getValue();
  return {};
}

// Only when the entry is the use's one reader: a match that read the used
// value and a region that enters it again would otherwise both use the
// linear value on one path.
OpFoldResult LinEnterOp::fold(FoldAdaptor) {
  if (auto use = getValue().getDefiningOp<LinUseOp>())
    if (use.getResult().hasOneUse())
      return use.getLinear();
  return {};
}
