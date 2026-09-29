// idr.facts:functions: the facts of a function, `idr.effects`, `idr.total`
// and `idr.library`, and whether it takes a world.
export module idr.facts:functions;

import idr.mlir;

import :effects;

export namespace idr::facts {

// What a call of `fn` may do. A null function (one the module lacks), a
// function without a body, or one without `idr.effects` may do anything;
// one without `idr.total` may not return.
Effects of(mlir::func::FuncOp fn);

// Writes what idr-effects found, `io` and `crash`, as `idr.effects`; whether
// `fn` returns is Idris's fact, `idr.total`.
void record(mlir::func::FuncOp fn, Effects effects);

// Gives `made`, a new function that runs the body of `origin` with closures
// of `labels` in it (a clone), the facts idr-effects would find: those of
// `origin` and of `labels` together (a null label, one not known, may do
// anything), and IO if it takes a world.
void inherit(mlir::func::FuncOp made, mlir::func::FuncOp origin,
             llvm::ArrayRef<mlir::func::FuncOp> labels);

// Whether `fn` was written in a library module.
bool isLibrary(mlir::func::FuncOp fn);

// Whether a value of `type` may hold a world: a world, or data with a field
// that may; a linear value holds what its value does. A closure never
// captures one, so a world reaches a function only through its parameters.
bool mayHoldWorld(mlir::Operation *from, mlir::Type type);

// Whether `fn` takes a world, in a parameter or in data one holds.
bool takesWorld(mlir::func::FuncOp fn);

} // namespace idr::facts
