// idr.ranges:sub: the bounds of a difference.
export module idr.ranges:sub;

import idr.mlir;

import :bounds;

namespace {

// Both bounds known: their difference cannot overflow an i64, since each is
// inside the small range.
std::optional<int64_t> minus(std::optional<int64_t> x, std::optional<int64_t> y) noexcept {
  if (x && y)
    return *x - *y;
  return std::nullopt;
}

} // namespace

export namespace idr::ranges {

Bounds sub(Bounds a, Bounds b) noexcept { return bounded(minus(a.lo, b.hi), minus(a.hi, b.lo)); }

} // namespace idr::ranges
