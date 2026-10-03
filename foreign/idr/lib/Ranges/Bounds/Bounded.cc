// Bounds kept only inside the small range.
module idr.ranges;

import idr.mlir;

namespace {

std::optional<int64_t> inside(std::optional<int64_t> v) noexcept {
  if (v && *v >= idr::ranges::smallMin && *v <= idr::ranges::smallMax)
    return v;
  return std::nullopt;
}

} // namespace

idr::ranges::Bounds idr::ranges::bounded(std::optional<int64_t> lo,
                                         std::optional<int64_t> hi) noexcept {
  return {inside(lo), inside(hi)};
}
