// idr.lin.enter and idr.lin.use: a value moved into a linear type, and
// used out of it.

#include "idr/Idr.h"

import idr.ops;

using namespace mlir;
using namespace idr;

// The value an entry used at once held, and the linear value a use entered
// at once was.
OpFoldResult LinUseOp::fold(FoldAdaptor) {
  if (auto enter = getLinear().getDefiningOp<LinEnterOp>())
    return enter.getValue();
  return {};
}

// Only when the entry is the use's one reader: a match that read the used
// value and a region that enters it again would otherwise both use the
// linear value on one path.
OpFoldResult LinEnterOp::fold(FoldAdaptor) {
  if (auto use = getValue().getDefiningOp<LinUseOp>())
    if (use.getResult().hasOneUse())
      return use.getLinear();
  return {};
}

// A linear value has the range of the value that entered it (idr.ops).
void LinEnterOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                               SetIntLatticeFn setResultRange) {
  if (!ranges.front().isUninitialized())
    ops::passRange(getResult(), ranges.front(), setResultRange);
}

void LinUseOp::inferResultRangesFromOptional(ArrayRef<IntegerValueRange> ranges,
                                             SetIntLatticeFn setResultRange) {
  if (ranges.front().isUninitialized() && getLinear().getDefiningOp<LinEnterOp>())
    return;
  ops::passRange(getResult(), ranges.front(), setResultRange);
}
