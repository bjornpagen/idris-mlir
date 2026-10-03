// idr.ranges:boundsof: the bounds a range states.
export module idr.ranges:boundsof;

import idr.mlir;

import :bounds;

export namespace idr::ranges {

// The bounds a range states. A range of another width, as MLIR gives a
// value that is not an integer, states none.
Bounds boundsOf(const mlir::ConstantIntRanges &range) noexcept {
  if (range.smin().getBitWidth() != 64)
    return {};
  return bounded(range.smin().getSExtValue(), range.smax().getSExtValue());
}

} // namespace idr::ranges
