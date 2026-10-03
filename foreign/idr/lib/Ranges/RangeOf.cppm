// idr.ranges:rangeof: the 64-bit range of bounds.
module;
// INT64_MIN and INT64_MAX, macros, which no import carries.
#include <cstdint>

export module idr.ranges:rangeof;

import idr.mlir;

import :bounds;

export namespace idr::ranges {

// The 64-bit range of `bounds`.
mlir::ConstantIntRanges rangeOf(Bounds bounds) noexcept {
  return mlir::ConstantIntRanges::fromSigned(
      mlir::APInt(64, static_cast<uint64_t>(bounds.lo.value_or(INT64_MIN)), /*isSigned=*/true),
      mlir::APInt(64, static_cast<uint64_t>(bounds.hi.value_or(INT64_MAX)), /*isSigned=*/true));
}

} // namespace idr::ranges
