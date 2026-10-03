// idr.ops:bigbounds: the ranges the ops on bigs and naturals state, from
// their bounds (idr.ranges).
export module idr.ops:bigbounds;

import idr.mlir;
import idr.dialect;
import idr.ranges;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// A natural is never negative, whatever its operands' ranges say.
ranges::Bounds ofType(ranges::Bounds bounds, Type type) {
  if (isa<NatType>(type) && (!bounds.lo || *bounds.lo < 0))
    bounds.lo = 0;
  return bounds;
}

// Sets the range of `result` to `bounds`, as its type has them.
void setBounds(Value result, ranges::Bounds bounds, SetIntRangeFn setResultRange) {
  setResultRange(result, ranges::rangeOf(ofType(bounds, result.getType())));
}

} // namespace idr::ops
