// Apply of a known closure.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

import idr.canon;

using namespace mlir;
using namespace idr;

// `idr.apply` of `idr.closure @f(caps)` or of a constant `#idr.closure<@f,
// [caps]>` is `func.call @f(caps..., args...)`, as upstream's
// CallIndirectOp::canonicalize turns an indirect call of a constant into a
// direct call; `inline` does the rest. A closure made here moves its
// captures into the call; one that captures a linear value has this apply
// as its one use, as the verifier requires.
LogicalResult ApplyOp::canonicalize(ApplyOp apply, PatternRewriter &rewriter) {
  Value closureValue = canon::closureOf(apply);
  FlatSymbolRefAttr callee;
  SmallVector<Value> operands;
  if (auto closure = closureValue.getDefiningOp<ClosureOp>()) {
    callee = closure.getCalleeAttr();
    llvm::append_range(operands, closure.getCaptures());
  } else if (ClosureAttr constant; matchPattern(closureValue, m_Constant(&constant))) {
    callee = constant.getCallee();
    auto fn = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(apply, callee);
    if (!fn || constant.getCaptures().size() > fn.getNumArguments())
      return failure();
    auto captures = llvm::zip(constant.getCaptures(), fn.getArgumentTypes());
    if (!llvm::all_of(captures, [](auto capture) {
          auto [value, type] = capture;
          return canon::buildable(value, type);
        }))
      return failure();
    for (auto [value, type] : captures)
      operands.push_back(canon::materialize(rewriter, apply.getLoc(), value, type));
  } else {
    return failure();
  }
  llvm::append_range(operands, apply.getArgs());
  rewriter.replaceOpWithNewOp<func::CallOp>(apply, callee, apply.getResultTypes(), operands);
  return success();
}
