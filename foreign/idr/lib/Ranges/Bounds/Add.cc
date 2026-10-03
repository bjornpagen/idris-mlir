// The bounds of a sum.
module idr.ranges;

import idr.mlir;

namespace {

// Both bounds known: their sum cannot overflow an i64, since each is inside
// the small range.
std::optional<int64_t> plus(std::optional<int64_t> x, std::optional<int64_t> y) noexcept {
  if (x && y)
    return *x + *y;
  return std::nullopt;
}

} // namespace

idr::ranges::Bounds idr::ranges::add(Bounds a, Bounds b) noexcept {
  return bounded(plus(a.lo, b.lo), plus(a.hi, b.hi));
}
