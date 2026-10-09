// idr.lin.enter and idr.lin.use: a value moved into a linear type, and
// used out of it.

#include "idr/Idr.h"

import idr.ops;

using namespace mlir;
using namespace idr;

// The value an entry used at once held, and the linear value a use entered
// at once was. A closure or a suspension holding a linear value is used
// once (holdsLinear), and the pair is that use: the ordinary value the use
// makes may be read many times, as a field of a shared constructor is, and
// the value takes its place only where it is taken once too.
OpFoldResult LinUseOp::fold(FoldAdaptor) {
  auto enter = getLinear().getDefiningOp<LinEnterOp>();
  if (!enter || (holdsLinear(enter.getValue()) && !takenOnce(getResult())))
    return {};
  return enter.getValue();
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
