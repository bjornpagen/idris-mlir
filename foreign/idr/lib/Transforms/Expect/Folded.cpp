// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// folded: a function's computation on constants is done, stated as what is
// not left: an op a fold would have replaced by constants. A fold replaces
// an op's results with constants computed from its operands' constant
// values, so such an op has results, constants alone as operands, and no
// memory effect or call that its results would stand in for. A greedy
// rewrite says whether it converged, not that a fold it could have made
// was never made, and `returns` states a function's results, not the ops
// that compute them; so the fuzzer's check that every closed expression
// folded is this property, asked through upstream's own questions of an
// op: its memory effects, the call interface and the constant trait.

#include "idr/Transforms/Expect.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/CallInterfaces.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::expect {

namespace {

// An op a fold would have replaced: it gives results, has no memory
// effect, is neither a call nor a constant, and takes constants alone. An
// op without results, a terminator, is nothing a fold replaces.
bool foldable(Operation *op) {
  auto constant = [](Value operand) { return matchPattern(operand, m_Constant()); };
  return op->getNumResults() != 0 && isMemoryEffectFree(op) && !isa<CallOpInterface>(op) &&
         !op->hasTrait<OpTrait::ConstantLike>() && llvm::all_of(op->getOperands(), constant);
}

} // namespace

// No op left in any copy of @f is one a fold would have replaced.
LogicalResult folded(ModuleOp module, AnalysisManager &, StringRef function) {
  constexpr StringRef property = "folded";
  SmallVector<FunctionOpInterface> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (FunctionOpInterface fn : functions)
    fn.getFunctionBody().walk([&](Operation *op) {
      if (!foldable(op))
        return;
      fail(op->getLoc(), property) << op->getName() << " in " << where(op)
                                   << " computes from constants alone and is left unfolded";
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
