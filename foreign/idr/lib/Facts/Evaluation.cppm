// idr.facts:evaluation: which calls idr-eval may run at compile time.
export module idr.facts:evaluation;

import idr.mlir;
import idr.dialect;

import :closurelabel;
import :of;

using namespace mlir;
using namespace idr;

namespace {

// Whether a call of `fn` may run at compile time: its body is here, and it
// performs no IO, which it could only with a world or through a function
// without a body. It may crash, or not return: the evaluation is metered,
// and what does not finish stays for runtime.
bool runs(func::FuncOp fn) { return fn && !fn.isExternal() && !facts::of(fn).io; }

} // namespace

export namespace idr::facts {

// A call idr-eval may run at compile time: a func.call, or an idr.apply of
// a constant closure, whose operands are all constants. `args` are the
// captures of the closure, then the operands. The callee and every
// function the constants name as closures have bodies and perform no IO; a
// crash or a call that does not finish stays for runtime. `total`: all of
// them are total, so the call runs with the larger budget.
struct Evaluation {
  mlir::func::FuncOp callee;
  llvm::SmallVector<mlir::Attribute> args;
  bool total;
};
std::optional<Evaluation> canEvaluate(Operation *op, SymbolTable &symbols) {
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
    // Poison, which remove-dead-values passes for a parameter nothing reads,
    // is no value to materialize.
    if (!matchPattern(operand, m_Constant(&value)) || isa<ub::PoisonAttr>(value))
      return std::nullopt;
    out.args.push_back(value);
  }
  // The callee, then every function the constants name as closures.
  out.callee = symbols.lookup<func::FuncOp>(callee.getAttr());
  SmallVector<func::FuncOp> runners{out.callee};
  for (Attribute arg : out.args)
    arg.walk([&](Attribute nested) {
      if (auto closure = dyn_cast<ClosureAttr>(nested))
        runners.push_back(symbols.lookup<func::FuncOp>(closure.getCallee().getAttr()));
      else if (auto con = dyn_cast<ConAttr>(nested))
        if (StringAttr name = closureLabel(op, con.getCtor()))
          runners.push_back(symbols.lookup<func::FuncOp>(name));
    });
  if (!llvm::all_of(runners, runs))
    return std::nullopt;
  out.total = llvm::none_of(runners, [](func::FuncOp fn) { return of(fn).diverge; });
  return out;
}

} // namespace idr::facts
