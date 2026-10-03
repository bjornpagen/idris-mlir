// The 64-bit range of bounds.
module;
// INT64_MIN and INT64_MAX, macros, which no import carries.
#include <cstdint>

module idr.ranges;

import idr.mlir;

mlir::ConstantIntRanges idr::ranges::rangeOf(Bounds bounds) noexcept {
  return mlir::ConstantIntRanges::fromSigned(
      mlir::APInt(64, static_cast<uint64_t>(bounds.lo.value_or(INT64_MIN)), /*isSigned=*/true),
      mlir::APInt(64, static_cast<uint64_t>(bounds.hi.value_or(INT64_MAX)), /*isSigned=*/true));
}
