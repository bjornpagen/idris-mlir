// Apply of a known closure.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"

using namespace mlir;
using namespace idr;

namespace {

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

// A constant capture, as the parameter it fills takes it: a linear
// parameter takes the constant entered into its linear type.
Value materialize(PatternRewriter &rewriter, Location loc, Attribute value, Type type) {
  Dialect *dialect = rewriter.getContext()->getLoadedDialect<IdrDialect>();
  Value plain = dialect->materializeConstant(rewriter, value, unrestricted(type), loc)->getResult(0);
  if (!isa<LinType>(type))
    return plain;
  return LinEnterOp::create(rewriter, loc, type, plain);
}

bool buildable(Attribute value, Type type) {
  return ConstantOp::isBuildableWith(value, unrestricted(type)) ||
         arith::ConstantOp::isBuildableWith(value, unrestricted(type));
}

} // namespace

// `idr.apply` of `idr.closure @f(caps)` or of a constant `#idr.closure<@f,
// [caps]>` is `func.call @f(caps..., args...)`, as upstream's
// CallIndirectOp::canonicalize turns an indirect call of a constant into a
// direct call; `inline` does the rest. A closure made here moves its
// captures into the call, so one that captures a linear value must die
// here: this apply is its only use.
LogicalResult ApplyOp::canonicalize(ApplyOp apply, PatternRewriter &rewriter) {
  Value closureValue = closureOf(apply);
  FlatSymbolRefAttr callee;
  SmallVector<Value> operands;
  if (auto closure = closureValue.getDefiningOp<ClosureOp>()) {
    bool linear = llvm::any_of(closure.getCaptures().getTypes(), llvm::IsaPred<LinType>);
    if (linear && !closure->hasOneUse())
      return failure();
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
          return buildable(value, type);
        }))
      return failure();
    for (auto [value, type] : captures)
      operands.push_back(materialize(rewriter, apply.getLoc(), value, type));
  } else {
    return failure();
  }
  llvm::append_range(operands, apply.getArgs());
  rewriter.replaceOpWithNewOp<func::CallOp>(apply, callee, apply.getResultTypes(), operands);
  return success();
}
