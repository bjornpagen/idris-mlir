// The conversions of scalars: to a character, a byte or an integer, and
// the first character of a number's text; when a division or a conversion
// may run before the guard of its operand; and idr.lin.enter and
// idr.lin.use, a value moved into a linear type and used out of it, whose
// ranges pass through.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"

#include "llvm/ADT/APSInt.h"

#include <cstdint>

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
  setResultRange(getResult(), idr::ranges::nonNegative(32, 0, 0x10FFFF));
}

// A value its guard refuses folds to nothing: the program never converts
// it, since the guard crashes first.
OpFoldResult ToByteOp::fold(FoldAdaptor adaptor) {
  if (!checkHolds(CheckKind::Byte, adaptor.getValue()))
    return {};
  return IntegerAttr::get(getType(), cast<IntegerAttr>(adaptor.getValue()).getValue().trunc(8));
}

void ToByteOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(8, 0, 255));
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
  setResultRange(getResult(), idr::ranges::nonNegative(32, '-', 'n'));
}

// '-' or a digit; a digit when unsigned.
void IntHeadOp::inferResultRanges(ArrayRef<ConstantIntRanges>, SetIntRangeFn setResultRange) {
  setResultRange(getResult(), idr::ranges::nonNegative(32, getIsSigned() ? '-' : '0', '9'));
}

//===----------------------------------------------------------------------===//
// The linear positions
//===----------------------------------------------------------------------===//

namespace {

// The range of any value of `type`, whose grade is no part of it: an
// integer's full width, a big's no bound, a natural's at least 0; none for a
// type without integers.
std::optional<IntegerValueRange> anyValue(Type type) {
  type = unrestricted(type);
  if (isa<BigType, NatType>(type))
    return IntegerValueRange(idr::ranges::rangeOf(
        isa<NatType>(type) ? idr::ranges::natural() : idr::ranges::Bounds{}));
  if (type.isIntOrIndex())
    return IntegerValueRange(ConstantIntRanges::maxRange(
        type.isIndex() ? IndexType::kInternalStorageBitWidth : type.getIntOrFloatBitWidth()));
  return std::nullopt;
}

// A linear value has the range of the value that entered it. MLIR's range
// analysis has no range for a value whose type is not an integer, so the
// linear value a parameter or a region binds has none; it starts at a
// range of the linear type, which states no width, and stands for any
// value.
void passRange(Value result, const IntegerValueRange &range, SetIntLatticeFn setResultRange) {
  std::optional<IntegerValueRange> any = anyValue(result.getType());
  if (!any)
    return;
  if (!range.isUninitialized() &&
      range.getValue().umin().getBitWidth() == any->getValue().umin().getBitWidth())
    setResultRange(result, range);
  else
    setResultRange(result, *any);
}

} // namespace

// The value an entry used at once held, and the linear value a use entered
// at once was. A closure or a suspension holding a linear value is used
// once (holdsLinear), and the pair is that use: the ordinary value the use
// makes may be read many times, as a field of a shared constructor is, and
// the value takes its place only where it is taken once too.
OpFoldResult LinUseOp::fold(FoldAdaptor) {
  auto enter = getLinear().getDefiningOp<LinEnterOp>();
  if (!enter || (holdsLinear(enter.getValue()) && !takenOnce(getResult())))
    return {};
  return enter.getValue();
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

// A linear value has the range of the value that entered it; its use then
// has every value of its type, where an entry's use waits for the entry's.
void LinEnterOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                               SetIntLatticeFn setResultRange) {
  if (!ranges.front().isUninitialized())
    passRange(getResult(), ranges.front(), setResultRange);
}

void LinUseOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                             SetIntLatticeFn setResultRange) {
  if (ranges.front().isUninitialized() && getLinear().getDefiningOp<LinEnterOp>())
    return;
  passRange(getResult(), ranges.front(), setResultRange);
}
