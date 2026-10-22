// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// folded: a function's computation on constants is done, stated as what is
// not left: an op a fold would have replaced by constants. A fold replaces
// an op's results with constants computed from its operands' constant
// values, so such an op has results, constants alone as operands, and does
// nothing but compute them, with everything in its regions, as the effect
// system's one query says; no call, whose results its callee computes, and
// no constant of its own. A greedy rewrite says whether it converged, not
// that a fold it could have made was never made; so the fuzzer's check that
// every closed expression folded is this property.

#include "Checks.h"

#include "idr/IR/Effects/Query.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

namespace {

// An op a fold would have replaced: it gives results, only computes them,
// is neither a call nor a constant, and takes constants alone. An op
// without results, a terminator, is nothing a fold replaces.
bool foldable(Operation *op) {
  auto constant = [](Value operand) { return matchPattern(operand, m_Constant()); };
  return op->getNumResults() != 0 && !isa<CallOpInterface>(op) &&
         !op->hasTrait<OpTrait::ConstantLike>() && llvm::all_of(op->getOperands(), constant) &&
         effects::whole(op).onlyComputes();
}

} // namespace

// No op left in any copy of @f is one a fold would have replaced.
LogicalResult folded(const Request<Functions> &request) {
  bool held = true;
  for (FunctionOpInterface fn : request.argument.functions)
    fn.getFunctionBody().walk([&](Operation *op) {
      if (!foldable(op))
        return;
      fail(op->getLoc(), request.property)
          << op->getName() << " in " << where(op)
          << " computes from constants alone and is left unfolded";
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
