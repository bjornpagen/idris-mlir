// Which calls idr-eval may run at compile time.

#include "Facts/Facts.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

namespace {

// Whether a call of `fn` may run at compile time: its body is here, and it
// performs no IO, which it could only with a world or through a function
// without a body. It may crash, or not return: the evaluation is metered,
// and what does not finish stays for runtime.
bool runs(func::FuncOp fn) { return fn && !fn.isExternal() && !facts::of(fn).io; }

} // namespace

std::optional<facts::Evaluation> facts::canEvaluate(Operation *op, SymbolTable &symbols) {
  Evaluation out;
  FlatSymbolRefAttr callee;
  ValueRange operands;
  if (auto call = dyn_cast<func::CallOp>(op)) {
    callee = call.getCalleeAttr();
    operands = call.getOperands();
  } else if (auto apply = dyn_cast<ApplyOp>(op)) {
    ClosureAttr closure;
    if (!matchPattern(apply.getCallee(), m_Constant(&closure)))
      return std::nullopt;
    callee = closure.getCallee();
    llvm::append_range(out.args, closure.getCaptures());
    operands = apply.getArgs();
  } else {
    return std::nullopt;
  }
  for (Value operand : operands) {
    Attribute value;
    // Poison, which idr-prune passes for a parameter nothing reads, is no
    // value to materialize.
    if (!matchPattern(operand, m_Constant(&value)) || isa<ub::PoisonAttr>(value))
      return std::nullopt;
    out.args.push_back(value);
  }
  out.callee = symbols.lookup<func::FuncOp>(callee.getAttr());
  if (!runs(out.callee))
    return std::nullopt;
  out.total = !of(out.callee).partial;
  bool labels = true;
  auto visit = [&](StringAttr name) {
    auto label = symbols.lookup<func::FuncOp>(name);
    labels &= runs(label);
    out.total &= labels && !of(label).partial;
  };
  for (Attribute arg : out.args)
    arg.walk([&](Attribute nested) {
      if (auto closure = dyn_cast<ClosureAttr>(nested))
        visit(closure.getCallee().getAttr());
      else if (auto con = dyn_cast<ConAttr>(nested))
        if (StringAttr name = closureLabel(con.getCtor()))
          visit(name);
    });
  if (!labels)
    return std::nullopt;
  return out;
}
