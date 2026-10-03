// The bounds of a difference.
module idr.ranges;

import idr.mlir;

namespace {

// Both bounds known: their difference cannot overflow an i64, since each is
// inside the small range.
std::optional<int64_t> minus(std::optional<int64_t> x, std::optional<int64_t> y) noexcept {
  if (x && y)
    return *x - *y;
  return std::nullopt;
}

} // namespace

idr::ranges::Bounds idr::ranges::sub(Bounds a, Bounds b) noexcept {
  return bounded(minus(a.lo, b.hi), minus(a.hi, b.lo));
}
