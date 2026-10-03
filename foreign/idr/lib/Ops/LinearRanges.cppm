// idr.ops:linearranges: a linear value has the range of the value that
// entered it. MLIR's range analysis has no range for a value whose type is
// not an integer, so the linear value a parameter or a region binds has
// none; its use then has every value of its type, where an entry's use
// waits for the entry's.
export module idr.ops:linearranges;

import idr.mlir;
import idr.dialect;
import idr.ranges;

using namespace mlir;
using namespace idr;

namespace {

// The range of any value of `type`, whose grade is no part of it: an
// integer's full width, a big's no bound, a natural's at least 0; none for a
// type without integers.
std::optional<IntegerValueRange> anyValue(Type type) {
  type = unrestricted(type);
  if (isa<BigType, NatType>(type))
    return IntegerValueRange(
        ranges::rangeOf(isa<NatType>(type) ? ranges::natural() : ranges::Bounds{}));
  if (type.isIntOrIndex())
    return IntegerValueRange(ConstantIntRanges::maxRange(
        type.isIndex() ? IndexType::kInternalStorageBitWidth : type.getIntOrFloatBitWidth()));
  return std::nullopt;
}

} // namespace

export namespace idr::ops {

// A linear value's range is its value's, which the grade must not hide. A
// linear value the analysis never saw computed (a field a match binds)
// starts at a range of the linear type, which states no width; it stands
// for any value.
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

} // namespace idr::ops
