// idr.facts:evaluation: which calls idr-eval may run at compile time.
export module idr.facts:evaluation;

import idr.mlir;

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
std::optional<Evaluation> canEvaluate(mlir::Operation *call, mlir::SymbolTable &symbols);

} // namespace idr::facts
