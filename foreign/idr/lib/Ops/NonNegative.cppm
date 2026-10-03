// idr.ops:nonnegative: a range from unsigned bounds: the ops whose results
// are never negative (a tag, a character, a byte, a length) state it so.
export module idr.ops:nonnegative;

import idr.mlir;

using namespace mlir;

export namespace idr::ops {

// A range of i32 or i64 values, all non-negative.
ConstantIntRanges nonNegative(unsigned width, uint64_t min, uint64_t max) {
  return ConstantIntRanges::fromUnsigned(APInt(width, min), APInt(width, max));
}

} // namespace idr::ops
