// idr.ranges:mul: the bounds of a product.
export module idr.ranges:mul;

import idr.mlir;

import :bounds;

export namespace idr::ranges {

// With every bound known, the least and greatest of the corners' products;
// with two non-negative factors, at least their lower bounds' product.
Bounds mul(Bounds a, Bounds b) noexcept {
  if (a.fits() && b.fits()) {
    std::optional<int64_t> corners[] = {
        llvm::checkedMul(*a.lo, *b.lo), llvm::checkedMul(*a.lo, *b.hi),
        llvm::checkedMul(*a.hi, *b.lo), llvm::checkedMul(*a.hi, *b.hi)};
    if (llvm::all_of(corners, [](std::optional<int64_t> c) { return c.has_value(); })) {
      auto [lo, hi] = std::minmax({*corners[0], *corners[1], *corners[2], *corners[3]});
      return bounded(lo, hi);
    }
  }
  if (a.lo && b.lo && *a.lo >= 0 && *b.lo >= 0)
    return bounded(llvm::checkedMul(*a.lo, *b.lo), std::nullopt);
  return {};
}

} // namespace idr::ranges
