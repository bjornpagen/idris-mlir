// idr.canon:closureof: the closure an apply runs, which its canonicalization
// turns into a call.
export module idr.canon:closureof;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::canon {

// The closure an apply runs: its callee, or, when the callee is the one use
// of a linear value made from a closure and nothing else uses either, that
// closure. The pair only moves the closure into a linear position and out
// again, so going around it uses nothing twice.
Value closureOf(ApplyOp apply) {
  Value callee = apply.getCallee();
  auto use = callee.getDefiningOp<LinUseOp>();
  if (!use || !callee.hasOneUse())
    return callee;
  auto enter = use.getLinear().getDefiningOp<LinEnterOp>();
  if (!enter || !enter->hasOneUse())
    return callee;
  return enter.getValue();
}

} // namespace idr::canon
