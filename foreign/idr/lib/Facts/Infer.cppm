// idr.facts:infer: what idr-effects finds, before it records it.
export module idr.facts:infer;

import idr.mlir;

import :effects;

export namespace idr::facts {

// Whether each function of `module` may perform IO, crash or diverge.
//
// A call of a function may perform IO when it takes a world, as a
// parameter or in data one holds. That is a fact of its type: a world
// reaches a function only through its parameters, since no op makes one
// from nothing (no constant is a world, and a closure never captures one).
// So a function that only builds IO actions, as a fold that makes
// `a *> b` does, performs no IO; whoever runs an action gives it a world.
//
// A function may crash when it reaches an op that may crash, through the
// functions it calls and the labels of the closures it makes: an
// idr.closure, a closure constant, or a constructor of a sum of closures
// that idr-defunctionalize made. A closure's crash counts where it is made,
// not where it is applied: a call that passes one on is judged by what the
// closure may do too (passed).
//
// A function may diverge when its own body may: it lacks `idr.total`,
// Idris's proof that every loop of it terminates. And it may when it
// reaches one that may, the same way as a crash. That holds through a
// function Idris proved too: its proof counts the calls Idris saw, and a
// call of an interface's method, which reaches the implementation only
// once the dictionary is known, is not one of them.
//
// A function without a body, and every function that reaches one or calls
// anything but a func.func, may do all three.
llvm::SmallVector<std::pair<mlir::func::FuncOp, Effects>> infer(mlir::ModuleOp module);

} // namespace idr::facts
