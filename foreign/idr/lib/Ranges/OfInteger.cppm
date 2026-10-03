// idr.ranges:ofinteger: the bounds of an integer operand.
module;
// INT64_MAX, a macro, which no import carries.
#include <cstdint>

export module idr.ranges:ofinteger;

import idr.mlir;

import :bounds;

export namespace idr::ranges {

// The bounds of an integer operand of range `range`, read as `isSigned`
// says.
Bounds ofInteger(const mlir::ConstantIntRanges &range, bool isSigned) noexcept {
  unsigned width = range.smin().getBitWidth();
  if (width == 0 || width > 64)
    return {};
  if (isSigned)
    return bounded(range.smin().getSExtValue(), range.smax().getSExtValue());
  // An unsigned 64-bit value above INT64_MAX is outside the small range.
  auto unsignedBound = [](const mlir::APInt &v) -> std::optional<int64_t> {
    if (v.getZExtValue() > static_cast<uint64_t>(INT64_MAX))
      return std::nullopt;
    return static_cast<int64_t>(v.getZExtValue());
  };
  return bounded(unsignedBound(range.umin()), unsignedBound(range.umax()));
}

} // namespace idr::ranges
