// idr.facts:functions: the facts of a function, `idr.effects`, `idr.total`
// and `idr.break_last`, and whether it takes a world.
export module idr.facts:functions;

import idr.mlir;

import :effects;

export namespace idr::facts {

// What a call of `fn` may do. A null function (one the module lacks), a
// function without a body, or one without `idr.effects` may do anything.
Effects of(mlir::func::FuncOp fn);

// Writes what idr-effects found as `idr.effects`.
void record(mlir::func::FuncOp fn, Effects effects);

// Gives `made`, a new function that runs the body of `origin` with closures
// of `labels` in it (a clone), the effects idr-effects would find: those of
// `origin` and of `labels` together (a null label, one not known, may do
// anything), and IO if it takes a world. Its `idr.total` is its origin's,
// which it was cloned with: its body loops where its origin's does.
void inherit(mlir::func::FuncOp made, mlir::func::FuncOp origin,
             llvm::ArrayRef<mlir::func::FuncOp> labels);

// `into`'s body has taken in a copy of `callee`'s (a null callee, one not
// known, has any body). `idr.total` says that every loop of a body is one
// Idris proved terminating; a body that takes in one without that proof
// loses it, since a loop of the callee's may close in it.
void inlined(mlir::func::FuncOp into, mlir::func::FuncOp callee);

// Whether a cycle of references breaks at `fn` only when it has no function
// that does not (`idr.break_last`, the registry's column).
bool breaksLast(mlir::func::FuncOp fn);

// Whether a value of `type` may hold a world: a world, or data with a field
// that may; a linear value holds what its value does. A closure never
// captures one, so a world reaches a function only through its parameters.
bool mayHoldWorld(mlir::Operation *from, mlir::Type type);

// Whether `fn` takes a world, in a parameter or in data one holds.
bool takesWorld(mlir::func::FuncOp fn);

} // namespace idr::facts
