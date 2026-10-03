// The bounds a range states.
module idr.ranges;

import idr.mlir;

idr::ranges::Bounds idr::ranges::boundsOf(const mlir::ConstantIntRanges &range) noexcept {
  if (range.smin().getBitWidth() != 64)
    return {};
  return bounded(range.smin().getSExtValue(), range.smax().getSExtValue());
}
