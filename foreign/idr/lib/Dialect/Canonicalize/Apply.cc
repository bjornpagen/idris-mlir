// Apply of a known closure.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

// `idr.apply` of `idr.closure @f(caps)` or of a constant `#idr.closure<@f,
// [caps]>` is `func.call @f(caps..., args...)`, as upstream's
// CallIndirectOp::canonicalize turns an indirect call of a constant into a
// direct call; `inline` does the rest.
LogicalResult ApplyOp::canonicalize(ApplyOp apply, PatternRewriter &rewriter) {
  FlatSymbolRefAttr callee;
  SmallVector<Value> operands;
  if (auto closure = apply.getCallee().getDefiningOp<ClosureOp>()) {
    callee = closure.getCalleeAttr();
    llvm::append_range(operands, closure.getCaptures());
  } else if (ClosureAttr constant; matchPattern(apply.getCallee(), m_Constant(&constant))) {
    callee = constant.getCallee();
    auto fn = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(apply, callee);
    if (!fn || constant.getCaptures().size() > fn.getNumArguments())
      return failure();
    auto captures = llvm::zip(constant.getCaptures(), fn.getArgumentTypes());
    Dialect *dialect = apply->getDialect();
    if (!llvm::all_of(captures, [](auto capture) {
          auto [value, type] = capture;
          return ConstantOp::isBuildableWith(value, type) ||
                 arith::ConstantOp::isBuildableWith(value, type);
        }))
      return failure();
    for (auto [value, type] : captures)
      operands.push_back(
          dialect->materializeConstant(rewriter, value, type, apply.getLoc())->getResult(0));
  } else {
    return failure();
  }
  llvm::append_range(operands, apply.getArgs());
  rewriter.replaceOpWithNewOp<func::CallOp>(apply, callee, apply.getResultTypes(), operands);
  return success();
}
